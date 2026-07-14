import Testing
import Foundation
import CoreKit
@testable import Networking

extension NetworkingTests {
    // MARK: - Observer

    @Test("2xx emits success only after decoding succeeds")
    func observationSucceedsAfterDecode() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let clock = SteppingObservationClock()
        let (client, _) = TestFactory.clientWithObserver(
            observer: spy,
            observationNow: clock.now
        )

        let _: BooksResponse = try await client.send(Endpoints.getBooks())
        let event = try #require(spy.events.only)
        #expect(event.method == .get)
        #expect(event.route == "/book/books")
        #expect(event.attempt == 1)
        #expect(event.elapsed == .milliseconds(25))
        #expect(event.outcome == .success)
        #expect(event.statusCode == 200)
        #expect(event.requestId == nil)
        #expect(event.retryDisposition == .final)
    }

    @Test("2xx decode failure emits decoding failure and never success")
    func observationRecordsDecodeFailure() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"unexpected":"private-body"}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .decoding")
        } catch let error as AppError {
            #expect(error.code == "decoding")
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .decodingFailure)
        #expect(event.statusCode == 200)
        #expect(!spy.events.contains { $0.outcome == .success })
    }

    @Test("HTTP failure preserves AppError and emits safe status and request ID")
    func observationRecordsHTTPFailure() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(
                statusCode: 404,
                body: TestFactory.errorEnvelope(
                    code: "not_found",
                    requestId: "req-httpfailure123456"
                )
            )
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)
        let endpoint = Endpoint(
            method: .get,
            path: "/book/books/private-book-id",
            query: [URLQueryItem(name: "referral", value: "private-code")],
            requiresAuth: false
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected .notFound")
        } catch let error as AppError {
            #expect(error == .notFound)
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .httpFailure)
        #expect(event.route == "/book/books/:id")
        #expect(event.statusCode == 404)
        #expect(event.requestId == "req-httpfailure123456")
        #expect(event.retryDisposition == .final)
    }

    @Test("transient network retries emit increasing attempts and a final failure")
    func observationRecordsNetworkRetryLifecycle() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.timedOut) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy, maxRetries: 2)

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .offline")
        } catch let error as AppError {
            #expect(error == .offline)
        }

        #expect(spy.events.map(\.attempt) == [1, 2, 3])
        #expect(spy.events.map(\.outcome) == [
            .networkFailure,
            .networkFailure,
            .networkFailure,
        ])
        #expect(spy.events.map(\.retryDisposition) == [
            .willRetry,
            .willRetry,
            .final,
        ])
    }

    @Test("cancellation emits cancellation and preserves CancellationError")
    func observationRecordsCancellation() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.cancelled) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy, maxRetries: 3)

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation must not be mapped to .offline.
        } catch {
            Issue.record("expected CancellationError, got \(type(of: error))")
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .cancellation)
        #expect(event.statusCode == nil)
        #expect(event.retryDisposition == .final)
    }

    @Test("token refresh retry remains exactly once and is observable per attempt")
    func observationRecordsTokenRefreshRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            index == 0
                ? .init(statusCode: 401, body: TestFactory.errorEnvelope(code: "unauthenticated"))
                : .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, provider) = TestFactory.clientWithObserver(observer: spy, token: "stale")

        let response: SessionResponse = try await client.send(Endpoints.getSession())

        #expect(response.loggedIn)
        #expect(await provider.currentRefreshCount() == 1)
        #expect(spy.events.map(\.attempt) == [1, 2])
        #expect(spy.events.map(\.outcome) == [.httpFailure, .success])
        #expect(spy.events.map(\.retryDisposition) == [.willRetry, .final])
    }

    @Test("step-up retry remains exactly once and is observable per attempt")
    func observationRecordsStepUpRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            index == 0
                ? .init(statusCode: 401, body: TestFactory.errorEnvelope(code: "reauth_required"))
                : .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, provider) = TestFactory.clientWithObserver(observer: spy, token: "stale")

        let response: SessionResponse = try await client.send(Endpoints.getSession())

        #expect(response.loggedIn)
        #expect(await provider.currentStepUpCount() == 1)
        #expect(spy.events.map(\.attempt) == [1, 2])
        #expect(spy.events.map(\.outcome) == [.httpFailure, .success])
        #expect(spy.events.map(\.retryDisposition) == [.willRetry, .final])
    }

    @Test("sendData success emits one success event without changing bytes")
    func sendDataObservationSuccess() async throws {
        StubURLProtocol.reset()
        let expected = Data("private export bytes".utf8)
        StubURLProtocol.responder = { _ in .init(statusCode: 200, body: expected) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        let data = try await client.sendData(Endpoints.getExport())

        #expect(data == expected)
        let event = try #require(spy.events.only)
        #expect(event.outcome == .success)
        #expect(event.route == "/book/me/export")
        #expect(event.statusCode == 200)
    }

    @Test("sendData HTTP failure emits one HTTP event and preserves AppError")
    func sendDataObservationHTTPFailure() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(
                statusCode: 500,
                body: TestFactory.errorEnvelope(
                    code: "internal_error",
                    requestId: "req-exportfailure123456"
                )
            )
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do {
            _ = try await client.sendData(Endpoints.getExport())
            Issue.record("expected server AppError")
        } catch let error as AppError {
            #expect(error.code == "internal_error")
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .httpFailure)
        #expect(event.statusCode == 500)
        #expect(event.requestId == "req-exportfailure123456")
    }

    @Test("sendData network failure emits one event and preserves URLError")
    func sendDataObservationNetworkFailure() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.notConnectedToInternet) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do {
            _ = try await client.sendData(Endpoints.getExport())
            Issue.record("expected URLError")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .networkFailure)
        #expect(event.statusCode == nil)
    }

    @Test("sendData cancellation emits cancellation and preserves CancellationError")
    func sendDataObservationCancellation() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.cancelled) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do {
            _ = try await client.sendData(Endpoints.getExport())
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(type(of: error))")
        }

        let event = try #require(spy.events.only)
        #expect(event.outcome == .cancellation)
        #expect(event.statusCode == nil)
    }

    @Test("event reflection excludes query, token, body, raw error, and dynamic identifiers")
    func observationPrivacyBoundary() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            throw URLError(
                .timedOut,
                userInfo: [NSLocalizedDescriptionKey: "raw-private-error"]
            )
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(
            observer: spy,
            token: "private-token",
            maxRetries: 0
        )
        let endpoint = Endpoint(
            method: .post,
            path: "/book/books/private-book-id/chapters/7",
            query: [URLQueryItem(name: "code", value: "private-query")],
            httpBody: Data("private-body".utf8),
            requiresAuth: true
        )

        do {
            let _: BooksResponse = try await client.send(endpoint)
        } catch {}

        let event = try #require(spy.events.only)
        let reflected = String(reflecting: event)
        #expect(event.route == "/book/books/:id/chapters/:number")
        for forbidden in [
            "private-book-id",
            "private-query",
            "private-token",
            "private-body",
            "raw-private-error",
            "URLError",
            "timedOut",
        ] {
            #expect(!reflected.contains(forbidden))
        }
    }
}
