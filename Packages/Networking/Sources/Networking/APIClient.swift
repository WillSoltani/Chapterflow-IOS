import Foundation
import CoreKit

/// The abstraction feature packages depend on, so they can be tested against
/// ``MockAPIClient`` without touching the network.
public protocol APIClientProtocol: Sendable {
    /// Sends the endpoint and decodes a success body directly into `T`.
    /// Throws an `AppError` on any failure.
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
}

/// A typed, async API client for the ChapterFlow REST API.
///
/// Responsibilities:
/// - Build a `URLRequest` from an ``Endpoint`` against `AppConfig.apiBaseURL`.
/// - Inject `Authorization: Bearer <id_token>` (from ``TokenProviding``) when
///   the endpoint requires auth.
/// - Decode a 2xx body **directly** into the requested `Decodable` (the success
///   envelope is the raw JSON object), or decode the error envelope on non-2xx
///   and throw a mapped `AppError`.
/// - Resilience: one automatic token refresh + retry on `401 unauthenticated`;
///   exponential backoff (up to `maxRetries`) on `.verifierUnavailable` and
///   transient `URLError`s; surface `Retry-After` on `429`.
///
/// It is an `actor` so its (small) mutable configuration and the refresh/retry
/// bookkeeping are isolated; the heavy lifting is a `URLSession` call.
public actor APIClient: APIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProviding
    private let logger: RequestLogging?
    private let maxRetries: Int
    private let retryBaseDelay: Duration

    /// Designated initializer.
    /// - Parameters:
    ///   - baseURL: the API base URL (usually `AppConfig.apiBaseURL`).
    ///   - tokenProvider: supplies/refreshes the Cognito `id_token`.
    ///   - session: the URLSession (injectable for stubbed tests).
    ///   - logger: optional debug request logger.
    ///   - maxRetries: max backoff retries for transient failures.
    ///   - retryBaseDelay: base delay for exponential backoff (tests pass `.zero`).
    public init(
        baseURL: URL,
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        logger: RequestLogging? = nil,
        maxRetries: Int = 3,
        retryBaseDelay: Duration = .milliseconds(300)
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.logger = logger
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
    }

    /// Convenience initializer reading the base URL from `AppConfig`.
    public init(
        config: AppConfig,
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        logger: RequestLogging? = nil,
        maxRetries: Int = 3,
        retryBaseDelay: Duration = .milliseconds(300)
    ) {
        // An unparsable base URL yields requests that fail as `.offline`, which
        // is the correct user-facing outcome for a misconfigured build.
        let url = URL(string: config.apiBaseURL) ?? URL(string: "https://invalid.chapterflow.invalid")!
        self.init(
            baseURL: url,
            tokenProvider: tokenProvider,
            session: session,
            logger: logger,
            maxRetries: maxRetries,
            retryBaseDelay: retryBaseDelay
        )
    }

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        var backoffAttempt = 0
        var didRefreshToken = false

        while true {
            try Task.checkCancellation()
            let request = try await makeRequest(for: endpoint)
            logger?.logRequest(request)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AppError.offline
                }
                logger?.logResponse(http, data: data, for: request)

                if (200..<300).contains(http.statusCode) {
                    return try decode(data)
                }

                let error = ErrorMapper.map(
                    status: http.statusCode,
                    data: data,
                    retryAfter: Self.retryAfter(from: http)
                )

                // One-time refresh + retry when the token was rejected.
                if case .unauthenticated = error, endpoint.requiresAuth, !didRefreshToken {
                    didRefreshToken = true
                    try await tokenProvider.refresh()
                    continue
                }

                // Backoff on a transient auth-verifier outage.
                if case .verifierUnavailable = error, backoffAttempt < maxRetries {
                    backoffAttempt += 1
                    try await backoff(backoffAttempt)
                    continue
                }

                throw error
            } catch let urlError as URLError {
                logger?.logFailure(urlError, for: request)
                if urlError.code == .cancelled {
                    throw CancellationError()
                }
                if Self.isTransient(urlError), backoffAttempt < maxRetries {
                    backoffAttempt += 1
                    try await backoff(backoffAttempt)
                    continue
                }
                throw AppError.offline
            }
        }
    }

    // MARK: - Request building

    private func makeRequest(for endpoint: Endpoint) async throws -> URLRequest {
        // Join base + path via string so a multi-segment path with a leading
        // slash is preserved exactly (`appendingPathComponent` percent-encodes
        // interior slashes).
        var base = baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + endpoint.path) else {
            throw AppError.offline
        }
        if !endpoint.query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + endpoint.query
        }
        guard let url = components.url else {
            throw AppError.offline
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        if let body = endpoint.httpBody {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.requiresAuth {
            guard let token = try await tokenProvider.validToken() else {
                throw AppError.unauthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        // A 204/empty body decoding into a `Void`-like type isn't modeled here;
        // callers always request a concrete `Decodable` matching the route.
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }

    // MARK: - Retry helpers

    private func backoff(_ attempt: Int) async throws {
        // Exponential: base * 2^(attempt-1). `attempt` is 1-based.
        let factor = 1 << (attempt - 1)
        try await Task.sleep(for: retryBaseDelay * factor)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // The header may be a number of seconds or an HTTP date; we support the
        // (far more common) seconds form.
        return TimeInterval(value.trimmingCharacters(in: .whitespaces))
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
