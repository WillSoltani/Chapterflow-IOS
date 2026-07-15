import CoreKit
import Foundation
import Testing
@testable import Networking

extension NetworkingTests {
    @Test("HTTP methods receive conservative reliability defaults")
    func reliabilityDefaultsByMethod() {
        #expect(Endpoint(method: .get, path: "/read").reliabilityPolicy.retryPolicy
                == .boundedTransientRead(maxRetries: 3))
        for method in [HTTPMethod.post, .patch, .put, .delete] {
            #expect(Endpoint(method: method, path: "/write").reliabilityPolicy.retryPolicy == .none)
        }
    }

    @Test("transient GET retries and succeeds within its endpoint bound")
    func transientGETRetriesAndSucceeds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            if index == 0 { throw URLError(.timedOut) }
            return .init(statusCode: 200, body: #"{"books":["kept"]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client(maxRetries: 3)
        let endpoint = endpoint(
            method: .get,
            policy: policy(retryPolicy: .boundedTransientRead(maxRetries: 1))
        )

        let response: BooksResponse = try await client.send(endpoint)

        #expect(response.books == ["kept"])
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("transient GET stops at the endpoint retry bound")
    func transientGETStopsAtBound() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.networkConnectionLost) }
        let (client, _) = TestFactory.client(maxRetries: 3)
        let endpoint = endpoint(
            method: .get,
            policy: policy(retryPolicy: .boundedTransientRead(maxRetries: 1))
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected .offline")
        } catch let error as AppError {
            #expect(error == .offline)
        }
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("transport cancellation remains CancellationError and never retries")
    func transportCancellationDoesNotRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.cancelled) }
        let (client, _) = TestFactory.client(maxRetries: 3)

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("cancellation during injected backoff stops before another attempt")
    func backoffCancellationDoesNotRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.timedOut) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(
            observer: spy,
            maxRetries: 3,
            sleeper: { _ in throw CancellationError() }
        )

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        #expect(StubURLProtocol.requestCount == 1)
        #expect(spy.events.count == 1)
        #expect(spy.events.only?.outcome == .networkFailure)
        #expect(spy.events.only?.retryDisposition == .final)
    }

    @Test(
        "POST, PATCH, PUT, and DELETE cannot enable transient replay",
        arguments: [HTTPMethod.post, .patch, .put, .delete]
    )
    func writesDoNotRetry(method: HTTPMethod) async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.timedOut) }
        let (client, _) = TestFactory.client(maxRetries: 3)
        let endpoint = endpoint(
            method: method,
            policy: policy(retryPolicy: .boundedTransientRead(maxRetries: 3))
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected .offline")
        } catch let error as AppError {
            #expect(error == .offline)
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("verifier-unavailable never replays a write even with a read override")
    func verifierUnavailableDoesNotReplayWrite() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 503, body: TestFactory.errorEnvelope(code: "verifier_unavailable"))
        }
        let (client, provider) = TestFactory.client(maxRetries: 3)
        let endpoint = endpoint(
            method: .post,
            policy: policy(retryPolicy: .boundedTransientRead(maxRetries: 3))
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected .verifierUnavailable")
        } catch let error as AppError {
            #expect(error == .verifierUnavailable)
        }

        #expect(StubURLProtocol.requestCount == 1)
        #expect(await provider.currentReportedErrors() == [.verifierUnavailable])
    }

    @Test(
        "auth failures never replay POST, PATCH, PUT, or DELETE",
        arguments: [HTTPMethod.post, .patch, .put, .delete],
        ["unauthenticated", "reauth_required"]
    )
    func writeAuthFailuresDoNotReplay(method: HTTPMethod, code: String) async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 401, body: TestFactory.errorEnvelope(code: code))
        }
        let (client, provider) = TestFactory.client(token: "stale")
        let endpoint = Endpoint(method: method, path: "/write-auth", requiresAuth: true)
        let expectedError: AppError = code == "unauthenticated" ? .unauthenticated : .reauthRequired

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected \(expectedError)")
        } catch let error as AppError {
            #expect(error == expectedError)
        }

        #expect(StubURLProtocol.requestCount == 1)
        #expect(await provider.currentRefreshCount() == 0)
        #expect(await provider.currentStepUpCount() == 0)
    }

    @Test("persistent reauth invokes step-up exactly once")
    func persistentReauthStepsUpOnlyOnce() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 401, body: TestFactory.errorEnvelope(code: "reauth_required"))
        }
        let (client, provider) = TestFactory.client(token: "stale")

        do {
            let _: SessionResponse = try await client.send(Endpoints.getSession())
            Issue.record("expected .reauthRequired")
        } catch let error as AppError {
            #expect(error == .reauthRequired)
        }

        #expect(await provider.currentStepUpCount() == 1)
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test(
        "malformed Retry-After values remain nil",
        arguments: ["later", "-1", "nan", "inf"]
    )
    func malformedRetryAfterIsNil(value: String) async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(
                statusCode: 429,
                body: TestFactory.errorEnvelope(code: "rate_limited"),
                headers: ["Retry-After": value]
            )
        }
        let (client, _) = TestFactory.client()

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .rateLimited")
        } catch let error as AppError {
            #expect(error == .rateLimited(retryAfter: nil))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("missing Retry-After remains nil")
    func missingRetryAfterIsNil() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 429, body: TestFactory.errorEnvelope(code: "rate_limited"))
        }
        let (client, _) = TestFactory.client()

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .rateLimited")
        } catch let error as AppError {
            #expect(error == .rateLimited(retryAfter: nil))
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("default success policy accepts 201")
    func defaultSuccessStatusAccepts201() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 201, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let response: BooksResponse = try await client.send(Endpoints.getBooks())

        #expect(response.books.isEmpty)
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("exact success policy accepts only its expected status")
    func exactSuccessStatusIsEnforced() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()
        let endpoint = endpoint(
            method: .get,
            policy: policy(successStatusPolicy: .exact([201]))
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected a status-policy failure")
        } catch let error as AppError {
            #expect(error.code == "server")
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("disallowed empty success body becomes a decoding failure")
    func disallowedEmptyBodyFails() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in .init(statusCode: 204) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do {
            let _: EmptyResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .decoding")
        } catch let error as AppError {
            #expect(error.code == "decoding")
        }

        #expect(spy.events.only?.outcome == .decodingFailure)
        #expect(spy.events.only?.statusCode == 204)
    }

    @Test("allowed empty success body decodes an explicit empty response")
    func allowedEmptyBodySucceeds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in .init(statusCode: 204) }
        let (client, _) = TestFactory.client()
        let endpoint = endpoint(
            method: .get,
            policy: policy(emptyBodyPolicy: .allowed)
        )

        let response: EmptyResponse = try await client.send(endpoint)

        #expect(response == EmptyResponse())
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("sendData applies GET retry policy and preserves returned bytes")
    func sendDataRetriesSafeRead() async throws {
        StubURLProtocol.reset()
        let expected = Data("export".utf8)
        StubURLProtocol.responder = { index in
            if index == 0 { throw URLError(.networkConnectionLost) }
            return .init(statusCode: 200, body: expected)
        }
        let (client, _) = TestFactory.client(maxRetries: 1)

        let result = try await client.sendData(Endpoints.getExport())

        #expect(result == expected)
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("sendData honors an explicit allowed empty body")
    func sendDataAllowsEmptyBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in .init(statusCode: 204) }
        let (client, _) = TestFactory.client()
        var endpoint = Endpoints.getExport()
        endpoint.reliabilityPolicy = policy(emptyBodyPolicy: .allowed)

        let result = try await client.sendData(endpoint)

        #expect(result.isEmpty)
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("request timeout comes from the endpoint policy")
    func requestUsesEndpointTimeout() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()
        let endpoint = endpoint(method: .get, policy: policy(timeout: 12.5))

        let _: BooksResponse = try await client.send(endpoint)

        #expect(StubURLProtocol.recordedRequests.only?.timeoutInterval == 12.5)
    }

    @Test("one observation is emitted per attempt with one request-start context")
    func observationsMatchAttemptsAndShareStartContext() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            if index == 0 { throw URLError(.timedOut) }
            return .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(
            observer: spy,
            maxRetries: 1
        )

        let _: BooksResponse = try await client.send(Endpoints.getBooks())

        #expect(StubURLProtocol.requestCount == 2)
        #expect(spy.events.count == 2)
        #expect(spy.events.map(\.attempt) == [1, 2])
        #expect(spy.events.map(\.retryDisposition) == [.willRetry, .final])
        #expect(spy.captureCount == 1)
    }
}

private struct EmptyResponse: Decodable, Sendable, Equatable {}

private func endpoint(
    method: HTTPMethod,
    policy: EndpointReliabilityPolicy
) -> Endpoint {
    var endpoint = Endpoint(method: method, path: "/reliability", requiresAuth: false)
    endpoint.reliabilityPolicy = policy
    return endpoint
}

private func policy(
    timeout: TimeInterval = 60,
    retryPolicy: EndpointReliabilityPolicy.RetryPolicy = .boundedTransientRead(maxRetries: 3),
    successStatusPolicy: EndpointReliabilityPolicy.SuccessStatusPolicy = .successfulResponses,
    emptyBodyPolicy: EndpointReliabilityPolicy.EmptyBodyPolicy = .disallowed
) -> EndpointReliabilityPolicy {
    EndpointReliabilityPolicy(
        timeout: timeout,
        retryPolicy: retryPolicy,
        successStatusPolicy: successStatusPolicy,
        emptyBodyPolicy: emptyBodyPolicy
    )
}
