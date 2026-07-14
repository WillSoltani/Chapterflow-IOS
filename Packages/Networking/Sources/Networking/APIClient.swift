import Foundation
import CoreKit

/// The abstraction feature packages depend on, so they can be tested against
/// ``MockAPIClient`` without touching the network.
public protocol APIClientProtocol: Sendable {
    /// Sends the endpoint and decodes a success body directly into `T`.
    /// Throws an `AppError` on any failure.
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T

    /// Sends the endpoint, decodes the success body into `T`, and also returns
    /// the server-clock `Date` from the HTTP `Date` response header (or `nil`
    /// when absent). Use the server date to anchor countdowns to server time
    /// instead of device time — important when the device clock may be skewed.
    func sendWithServerDate<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (T, Date?)

    /// Sends the endpoint and returns the raw response bytes without JSON decoding.
    /// Used for binary/export endpoints where the caller needs the raw payload.
    func sendData(_ endpoint: Endpoint) async throws -> Data
}

// Default implementations so existing conformers only need to implement `send`.
public extension APIClientProtocol {
    func sendWithServerDate<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (T, Date?) {
        let result: T = try await send(endpoint)
        return (result, nil)
    }

    /// Default implementation for binary/export endpoints. Preview clients inherit
    /// this so they don't need to implement `sendData` unless they need it.
    func sendData(_ endpoint: Endpoint) async throws -> Data {
        throw AppError.offline
    }
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
/// - Observability: emits one typed, privacy-safe event for every actual network
///   attempt, after its outcome is known (never bodies, tokens, queries, or errors).
///
/// It is an `actor` so its (small) mutable configuration and the refresh/retry
/// bookkeeping are isolated; the heavy lifting is a `URLSession` call.
public actor APIClient: APIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProviding
    private let logger: RequestLogging?
    let observer: any APIClientObserver
    private let maxRetries: Int
    private let retryBaseDelay: Duration
    let observationNow: @Sendable () -> ContinuousClock.Instant

    /// Designated initializer.
    /// - Parameters:
    ///   - baseURL: the API base URL (usually `AppConfig.apiBaseURL`).
    ///   - tokenProvider: supplies/refreshes the Cognito `id_token`.
    ///   - session: the URLSession (injectable for stubbed tests).
    ///   - logger: optional debug request logger.
    ///   - observer: optional observer for breadcrumbs / tracing (no PII).
    ///   - maxRetries: max backoff retries for transient failures.
    ///   - retryBaseDelay: base delay for exponential backoff (tests pass `.zero`).
    ///   - observationNow: monotonic time source for deterministic attempt timing.
    public init(
        baseURL: URL,
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        logger: RequestLogging? = nil,
        observer: (any APIClientObserver)? = nil,
        maxRetries: Int = 3,
        retryBaseDelay: Duration = .milliseconds(300),
        observationNow: @escaping @Sendable () -> ContinuousClock.Instant = {
            ContinuousClock().now
        }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.logger = logger
        self.observer = observer ?? NoopAPIClientObserver()
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
        self.observationNow = observationNow
    }

    /// Convenience initializer reading the base URL from `AppConfig`.
    public init(
        config: AppConfig,
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        logger: RequestLogging? = nil,
        observer: (any APIClientObserver)? = nil,
        maxRetries: Int = 3,
        retryBaseDelay: Duration = .milliseconds(300),
        observationNow: @escaping @Sendable () -> ContinuousClock.Instant = {
            ContinuousClock().now
        }
    ) {
        // An unparsable base URL yields requests that fail as `.offline`, which
        // is the correct user-facing outcome for a misconfigured build.
        let url = URL(string: config.apiBaseURL) ?? URL(string: "https://invalid.chapterflow.invalid")!
        self.init(
            baseURL: url,
            tokenProvider: tokenProvider,
            session: session,
            logger: logger,
            observer: observer,
            maxRetries: maxRetries,
            retryBaseDelay: retryBaseDelay,
            observationNow: observationNow
        )
    }

    // MARK: - APIClientProtocol

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let (result, _): (T, HTTPURLResponse) = try await performRequest(endpoint)
        return result
    }

    public func sendWithServerDate<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (T, Date?) {
        let (result, http): (T, HTTPURLResponse) = try await performRequest(endpoint)
        return (result, Self.serverDate(from: http))
    }

    public func sendData(_ endpoint: Endpoint) async throws -> Data {
        let observation = APIClientObservationAttempt(
            number: 1,
            started: observationNow(),
            context: observer.captureContext()
        )
        let request = try await makeRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .cancellation
            )
            throw CancellationError()
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                recordObservation(
                    request: request,
                    observation: observation,
                    outcome: .cancellation
                )
                throw CancellationError()
            }
            recordObservation(
                request: request,
                observation: observation,
                outcome: .networkFailure
            )
            // Preserve sendData's existing transport error behavior.
            throw urlError
        } catch {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .networkFailure
            )
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .networkFailure
            )
            throw AppError.offline
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = ErrorMapper.map(
                status: http.statusCode,
                data: data,
                retryAfter: Self.retryAfter(from: http)
            )
            recordObservation(
                request: request,
                observation: observation,
                outcome: .httpFailure,
                statusCode: http.statusCode,
                requestId: extractRequestId(from: data)
            )
            throw error
        }
        recordObservation(
            request: request,
            observation: observation,
            outcome: .success,
            statusCode: http.statusCode
        )
        return data
    }

    // MARK: - Core request loop

    /// Runs the full retry/refresh loop and returns the decoded value plus the
    /// final `HTTPURLResponse` (for callers that want response headers).
    private func performRequest<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (T, HTTPURLResponse) {
        let observationContext = observer.captureContext()
        var retryState = APIClientRetryState()
        var attemptNumber = 0

        while true {
            try Task.checkCancellation()
            let request = try await makeRequest(for: endpoint)
            logger?.logRequest(request)
            attemptNumber += 1
            let observation = APIClientObservationAttempt(
                number: attemptNumber,
                started: observationNow(),
                context: observationContext
            )

            switch try await performTransportAttempt(
                request,
                observation: observation,
                backoffAttempt: retryState.backoffAttempt
            ) {
            case let .retry(nextBackoffAttempt):
                retryState.backoffAttempt = nextBackoffAttempt
            case let .response(data, http):
                if (200..<300).contains(http.statusCode) {
                    return try decodeSuccessfulResponse(
                        data,
                        response: http,
                        request: request,
                        observation: observation
                    )
                }
                let failedAttempt = APIClientFailedHTTPAttempt(
                    request: request,
                    number: observation.number,
                    elapsed: elapsedSince(observation.started),
                    statusCode: http.statusCode,
                    requestId: extractRequestId(from: data),
                    observationContext: observation.context
                )
                retryState = try await retryStateAfterHTTPFailure(
                    endpoint: endpoint,
                    data: data,
                    response: http,
                    failedAttempt: failedAttempt,
                    currentState: retryState
                )
            }
        }
    }

    private func performTransportAttempt(
        _ request: URLRequest,
        observation: APIClientObservationAttempt,
        backoffAttempt: Int
    ) async throws -> APIClientTransportAttemptResult {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch is CancellationError {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .cancellation
            )
            throw CancellationError()
        } catch let urlError as URLError {
            return try await handleTransportError(
                urlError,
                request: request,
                observation: observation,
                backoffAttempt: backoffAttempt
            )
        } catch {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .networkFailure
            )
            throw error
        }

        guard let http = result.1 as? HTTPURLResponse else {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .networkFailure
            )
            throw AppError.offline
        }
        logger?.logResponse(http, data: result.0, for: request)
        return .response(result.0, http)
    }

    private func handleTransportError(
        _ urlError: URLError,
        request: URLRequest,
        observation: APIClientObservationAttempt,
        backoffAttempt: Int
    ) async throws -> APIClientTransportAttemptResult {
        logger?.logFailure(urlError, for: request)
        if urlError.code == .cancelled {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .cancellation
            )
            throw CancellationError()
        }

        let elapsed = elapsedSince(observation.started)
        guard Self.isTransient(urlError), backoffAttempt < maxRetries else {
            recordObservation(
                request: request,
                attempt: observation.number,
                elapsed: elapsed,
                outcome: .networkFailure,
                context: observation.context
            )
            throw AppError.offline
        }

        let nextBackoffAttempt = backoffAttempt + 1
        do {
            try await backoff(nextBackoffAttempt)
        } catch {
            recordObservation(
                request: request,
                attempt: observation.number,
                elapsed: elapsed,
                outcome: .networkFailure,
                context: observation.context
            )
            throw error
        }
        recordObservation(
            request: request,
            attempt: observation.number,
            elapsed: elapsed,
            outcome: .networkFailure,
            retryDisposition: .willRetry,
            context: observation.context
        )
        return .retry(nextBackoffAttempt: nextBackoffAttempt)
    }

    private func decodeSuccessfulResponse<T: Decodable & Sendable>(
        _ data: Data,
        response: HTTPURLResponse,
        request: URLRequest,
        observation: APIClientObservationAttempt
    ) throws -> (T, HTTPURLResponse) {
        do {
            let decoded: T = try decode(data)
            recordObservation(
                request: request,
                observation: observation,
                outcome: .success,
                statusCode: response.statusCode
            )
            return (decoded, response)
        } catch {
            recordObservation(
                request: request,
                observation: observation,
                outcome: .decodingFailure,
                statusCode: response.statusCode
            )
            throw error
        }
    }

    private func retryStateAfterHTTPFailure(
        endpoint: Endpoint,
        data: Data,
        response: HTTPURLResponse,
        failedAttempt: APIClientFailedHTTPAttempt,
        currentState: APIClientRetryState
    ) async throws -> APIClientRetryState {
        let mappedError = ErrorMapper.map(
            status: response.statusCode,
            data: data,
            retryAfter: Self.retryAfter(from: response)
        )
        if case .unauthenticated = mappedError,
           endpoint.requiresAuth,
           !currentState.didRefreshToken {
            var nextState = currentState
            nextState.didRefreshToken = true
            try await prepareRetry(
                .refreshToken,
                failedAttempt: failedAttempt
            )
            return nextState
        }
        if case .reauthRequired = mappedError,
           endpoint.requiresAuth,
           !currentState.didStepUp {
            var nextState = currentState
            nextState.didStepUp = true
            try await prepareRetry(
                .stepUp,
                failedAttempt: failedAttempt
            )
            return nextState
        }
        if case .verifierUnavailable = mappedError,
           currentState.backoffAttempt < maxRetries {
            var nextState = currentState
            nextState.backoffAttempt += 1
            try await prepareRetry(
                .backoff(nextState.backoffAttempt),
                failedAttempt: failedAttempt
            )
            return nextState
        }

        if case .verifierUnavailable = mappedError {
            await tokenProvider.reportSessionError(mappedError)
        }
        recordHTTPFailure(failedAttempt)
        throw mappedError
    }

    private func prepareRetry(
        _ preparation: APIClientRetryPreparation,
        failedAttempt: APIClientFailedHTTPAttempt
    ) async throws {
        do {
            switch preparation {
            case .refreshToken:
                try await tokenProvider.refresh()
            case .stepUp:
                try await tokenProvider.stepUp()
            case let .backoff(attempt):
                try await backoff(attempt)
            }
        } catch {
            recordHTTPFailure(failedAttempt)
            throw error
        }
        recordHTTPFailure(
            failedAttempt,
            retryDisposition: .willRetry
        )
    }

    private func recordHTTPFailure(
        _ failedAttempt: APIClientFailedHTTPAttempt,
        retryDisposition: APIRequestObservation.RetryDisposition = .final
    ) {
        recordObservation(
            request: failedAttempt.request,
            attempt: failedAttempt.number,
            elapsed: failedAttempt.elapsed,
            outcome: .httpFailure,
            statusCode: failedAttempt.statusCode,
            requestId: failedAttempt.requestId,
            retryDisposition: retryDisposition,
            context: failedAttempt.observationContext
        )
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

    /// Parses the RFC 1123 `Date` header from an HTTP response.
    /// Returns `nil` when the header is absent or unparseable.
    private static func serverDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")
        return formatter.date(from: value)
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
