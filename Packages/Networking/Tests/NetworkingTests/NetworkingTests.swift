import Testing
import Foundation
import CoreKit
@testable import Networking

/// Serialized because ``StubURLProtocol`` uses process-wide statics to record
/// requests and vend canned responses.
@Suite("Networking", .serialized)
struct NetworkingTests {

    // MARK: Envelope decode (success)

    @Test("2xx body decodes directly into the requested type")
    func decodesSuccessBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let session: SessionResponse = try await client.send(Endpoints.getSession())
        #expect(session == SessionResponse(loggedIn: true))
    }

    @Test("array-bearing success body decodes")
    func decodesCollectionBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":["a","b"]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let books: BooksResponse = try await client.send(Endpoints.getBooks())
        #expect(books.books == ["a", "b"])
    }

    @Test("a malformed success body throws .decoding")
    func malformedBodyThrowsDecoding() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"unexpected":1}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        await #expect(throws: AppError.self) {
            let _: SessionResponse = try await client.send(Endpoints.getSession())
        }
        do {
            let _: SessionResponse = try await client.send(Endpoints.getSession())
        } catch let error as AppError {
            #expect(error.code == "decoding")
        }
    }

    // MARK: Error-code mapping (one per case)

    @Test("401 (no reauth) → .unauthenticated")
    func maps401Unauthenticated() async throws {
        // Uses a no-auth endpoint so no refresh/retry masks the mapping.
        try await expectError(
            status: 401,
            code: "unauthenticated",
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .unauthenticated) }
    }

    @Test("401 with details.reauth → .reauthRequired")
    func maps401ReauthDetails() async throws {
        try await expectError(
            status: 401,
            code: "unauthenticated",
            reauth: true,
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .reauthRequired) }
    }

    @Test("401 with code reauth_required → .reauthRequired")
    func maps401ReauthCode() async throws {
        try await expectError(
            status: 401,
            code: "reauth_required",
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .reauthRequired) }
    }

    @Test("403 forbidden_origin → .forbidden")
    func maps403Forbidden() async throws {
        try await expectError(
            status: 403,
            code: "forbidden_origin",
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .forbidden) }
    }

    @Test("404 → .notFound")
    func maps404NotFound() async throws {
        try await expectError(
            status: 404,
            code: "not_found",
            endpoint: Endpoints.getBook(id: "missing")
        ) { #expect($0 == .notFound) }
    }

    @Test("429 → .rateLimited with parsed Retry-After")
    func maps429RateLimited() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(
                statusCode: 429,
                body: TestFactory.errorEnvelope(code: "rate_limited"),
                headers: ["Retry-After": "30"]
            )
        }
        let (client, _) = TestFactory.client()

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected an error")
        } catch let error as AppError {
            #expect(error == .rateLimited(retryAfter: 30))
        }
        // No auto-retry on 429 — one request only.
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("503 verifier_unavailable → .verifierUnavailable (after backoff)")
    func maps503Verifier() async throws {
        try await expectError(
            status: 503,
            code: "verifier_unavailable",
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .verifierUnavailable) }
    }

    @Test("400 invalid_* → .invalidInput(message)")
    func maps400InvalidInput() async throws {
        try await expectError(
            status: 400,
            code: "invalid_email",
            message: "Email is not valid.",
            endpoint: Endpoints.getBooks()
        ) { #expect($0 == .invalidInput("Email is not valid.")) }
    }

    @Test("unmapped status → .server(code:message:requestId:)")
    func mapsGenericServer() async throws {
        try await expectError(
            status: 500,
            code: "internal_error",
            message: "Boom",
            endpoint: Endpoints.getBooks()
        ) {
            #expect($0 == .server(code: "internal_error", message: "Boom", requestId: "req-123"))
        }
    }

    // MARK: Auth injection

    @Test("requiresAuth injects Bearer token")
    func injectsBearerToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client(token: "abc-123")

        let _: SessionResponse = try await client.send(Endpoints.getSession())
        let auth = StubURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer abc-123")
    }

    @Test("requiresAuth with no token throws .unauthenticated before any request")
    func missingTokenShortCircuits() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in .init(statusCode: 200) }
        let (client, _) = TestFactory.client(token: nil)

        do {
            let _: SessionResponse = try await client.send(Endpoints.getSession())
            Issue.record("expected .unauthenticated")
        } catch let error as AppError {
            #expect(error == .unauthenticated)
        }
        #expect(StubURLProtocol.requestCount == 0)
    }

    @Test("public endpoint sends no Authorization header")
    func publicEndpointHasNoAuth() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let _: BooksResponse = try await client.send(Endpoints.getBooks())
        let auth = StubURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == nil)
    }

    // MARK: 401 refresh + retry

    @Test("401 unauthenticated triggers one refresh then retries and succeeds")
    func refreshesAndRetriesOn401() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            index == 0
                ? .init(statusCode: 401, body: TestFactory.errorEnvelope(code: "unauthenticated"))
                : .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let (client, provider) = TestFactory.client(token: "stale")

        let session: SessionResponse = try await client.send(Endpoints.getSession())
        #expect(session == SessionResponse(loggedIn: true))
        #expect(await provider.currentRefreshCount() == 1)
        #expect(StubURLProtocol.requestCount == 2)
        // The retry carried the refreshed token.
        let retryAuth = StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Authorization")
        #expect(retryAuth == "Bearer refreshed-token")
    }

    @Test("persistent 401 refreshes only once then throws .unauthenticated")
    func refreshesOnlyOnce() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 401, body: TestFactory.errorEnvelope(code: "unauthenticated"))
        }
        let (client, provider) = TestFactory.client(token: "stale")

        do {
            let _: SessionResponse = try await client.send(Endpoints.getSession())
            Issue.record("expected .unauthenticated")
        } catch let error as AppError {
            #expect(error == .unauthenticated)
        }
        #expect(await provider.currentRefreshCount() == 1)
        #expect(StubURLProtocol.requestCount == 2) // original + one retry
    }

    // MARK: Backoff

    @Test("verifier_unavailable retries up to maxRetries then throws")
    func backsOffOnVerifierUnavailable() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 503, body: TestFactory.errorEnvelope(code: "verifier_unavailable"))
        }
        let (client, _) = TestFactory.client(maxRetries: 3)

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .verifierUnavailable")
        } catch let error as AppError {
            #expect(error == .verifierUnavailable)
        }
        #expect(StubURLProtocol.requestCount == 4) // initial + 3 retries
    }

    @Test("verifier_unavailable then success recovers within retry budget")
    func backoffRecovers() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            index < 2
                ? .init(statusCode: 503, body: TestFactory.errorEnvelope(code: "verifier_unavailable"))
                : .init(statusCode: 200, body: #"{"books":["x"]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client(maxRetries: 3)

        let books: BooksResponse = try await client.send(Endpoints.getBooks())
        #expect(books.books == ["x"])
        #expect(StubURLProtocol.requestCount == 3)
    }

    @Test("transient URLError retries then succeeds")
    func retriesTransientURLError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { index in
            if index == 0 { throw URLError(.timedOut) }
            return .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let books: BooksResponse = try await client.send(Endpoints.getBooks())
        #expect(books.books.isEmpty)
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test("non-transient URLError maps to .offline without retry")
    func nonTransientURLErrorIsOffline() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.notConnectedToInternet) }
        let (client, _) = TestFactory.client()

        do {
            let _: BooksResponse = try await client.send(Endpoints.getBooks())
            Issue.record("expected .offline")
        } catch let error as AppError {
            #expect(error == .offline)
        }
        #expect(StubURLProtocol.requestCount == 1)
    }

    // MARK: URL construction

    @Test("path and query items are composed onto the base URL")
    func buildsURLWithQuery() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"chapter":"c1"}"#.data(using: .utf8)!)
        }
        let (client, _) = TestFactory.client()

        let _: ChapterResponse = try await client.send(
            Endpoints.getChapter(bookId: "b1", n: 3, mode: "hard")
        )
        let url = StubURLProtocol.recordedRequests.first?.url
        #expect(url?.path() == "/book/books/b1/chapters/3")
        #expect(url?.query() == "mode=hard")
    }

    // MARK: - Observer

    @Test("2xx calls requestCompleted with method, path and status")
    func observerCalledOnSuccess() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":[]}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        let _: BooksResponse = try await client.send(Endpoints.getBooks())
        #expect(spy.completed.count == 1)
        #expect(spy.completed.first?.method == "GET")
        #expect(spy.completed.first?.status == 200)
        #expect(spy.failedCount == 0)
    }

    @Test("4xx calls requestCompleted with error status and requestId from envelope")
    func observerCalledOnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 404, body: TestFactory.errorEnvelope(code: "not_found", requestId: "req-xyz"))
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy)

        do { let _: BooksResponse = try await client.send(Endpoints.getBooks()) } catch {}
        #expect(spy.completed.first?.status == 404)
        #expect(spy.completed.first?.requestId == "req-xyz")
    }

    @Test("non-transient URLError calls requestFailed")
    func observerCalledOnNetworkError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in throw URLError(.notConnectedToInternet) }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy, maxRetries: 0)

        do { let _: BooksResponse = try await client.send(Endpoints.getBooks()) } catch {}
        #expect(spy.failedCount == 1)
        #expect(spy.completed.isEmpty)
    }

    @Test("observer path never contains auth token value")
    func observerPathHasNoToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"loggedIn":true}"#.data(using: .utf8)!)
        }
        let spy = SpyAPIClientObserver()
        let (client, _) = TestFactory.clientWithObserver(observer: spy, token: "super.secret.jwt")

        let _: SessionResponse = try await client.send(Endpoints.getSession())
        let call = try #require(spy.completed.first)
        #expect(!call.path.contains("super.secret.jwt"))
    }

    // MARK: - Helper

    /// Stubs a single error response and asserts the mapped `AppError`.
    private func expectError(
        status: Int,
        code: String,
        message: String = "Something went wrong.",
        reauth: Bool? = nil,
        endpoint: Endpoint,
        _ assert: (AppError) -> Void
    ) async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(
                statusCode: status,
                body: TestFactory.errorEnvelope(code: code, message: message, reauth: reauth)
            )
        }
        let (client, _) = TestFactory.client()

        do {
            let _: BooksResponse = try await client.send(endpoint)
            Issue.record("expected an error for status \(status)")
        } catch let error as AppError {
            assert(error)
        }
    }
}

// MARK: - AppError test equality

/// `AppError` isn't `Equatable` in CoreKit (its `.decoding` case wraps a
/// non-`Equatable` `Error`). These tests compare the cases they actually
/// produce, so a lightweight structural equality is defined here for assertions.
extension AppError: @retroactive Equatable {
    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated),
             (.reauthRequired, .reauthRequired),
             (.verifierUnavailable, .verifierUnavailable),
             (.forbidden, .forbidden),
             (.offline, .offline),
             (.notFound, .notFound):
            return true
        case let (.rateLimited(a), .rateLimited(b)):
            return a == b
        case let (.invalidInput(a), .invalidInput(b)):
            return a == b
        case let (.server(ca, ma, ra), .server(cb, mb, rb)):
            return ca == cb && ma == mb && ra == rb
        case let (.decoding(a), .decoding(b)):
            return (a as NSError) == (b as NSError)
        default:
            return false
        }
    }
}
