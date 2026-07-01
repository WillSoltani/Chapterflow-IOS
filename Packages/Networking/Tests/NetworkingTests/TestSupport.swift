import Foundation
@testable import Networking

// MARK: - Stubbed URLProtocol

/// A `URLProtocol` that serves canned responses and records every request.
///
/// Responses are provided by an index-based `responder` closure so a test can
/// return a *sequence* of outcomes (e.g. 401 then 200) to exercise the
/// refresh/retry and backoff paths. The `NetworkingTests` suite is `.serialized`
/// so these process-wide statics never race across tests.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int
        var body: Data
        var headers: [String: String]

        init(statusCode: Int, body: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    /// Returns the stub for the Nth request, or throws a `URLError` to simulate
    /// a transport failure.
    nonisolated(unsafe) static var responder: (@Sendable (Int) throws -> Stub)?
    /// Requests seen so far, in order (for asserting URLs and headers).
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset() {
        responder = nil
        recordedRequests = []
    }

    static var requestCount: Int { recordedRequests.count }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let index = Self.recordedRequests.count
        Self.recordedRequests.append(request)
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let stub = try responder(index)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Fake token provider

/// A configurable ``TokenProviding`` for tests. Tracks refresh calls and swaps
/// in a fresh token on refresh so the retry path can be observed end to end.
actor FakeTokenProvider: TokenProviding {
    private var token: String?
    private(set) var refreshCount = 0
    private let refreshedToken: String

    init(token: String?, refreshedToken: String = "refreshed-token") {
        self.token = token
        self.refreshedToken = refreshedToken
    }

    func validToken() async throws -> String? { token }

    func refresh() async throws {
        refreshCount += 1
        token = refreshedToken
    }

    func currentRefreshCount() -> Int { refreshCount }
}

// MARK: - Helpers

enum TestFactory {
    /// A URLSession wired to the stubbed protocol.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// An APIClient with instant backoff, backed by the stubbed session.
    static func client(
        token: String? = "initial-token",
        maxRetries: Int = 3
    ) -> (APIClient, FakeTokenProvider) {
        let provider = FakeTokenProvider(token: token)
        let client = APIClient(
            baseURL: URL(string: "https://api.chapterflow.test")!,
            tokenProvider: provider,
            session: session(),
            maxRetries: maxRetries,
            retryBaseDelay: .zero
        )
        return (client, provider)
    }

    /// Encodes an API error envelope body.
    static func errorEnvelope(
        code: String,
        message: String = "Something went wrong.",
        requestId: String? = "req-123",
        reauth: Bool? = nil
    ) -> Data {
        var error: [String: Any] = ["code": code, "message": message]
        if let requestId { error["requestId"] = requestId }
        if let reauth { error["details"] = ["reauth": reauth] }
        return try! JSONSerialization.data(withJSONObject: ["error": error])
    }
}

// MARK: - Sample decodable models

struct SessionResponse: Decodable, Sendable, Equatable {
    let loggedIn: Bool
}

struct BooksResponse: Decodable, Sendable, Equatable {
    let books: [String]
}

struct ChapterResponse: Decodable, Sendable, Equatable {
    let chapter: String
}
