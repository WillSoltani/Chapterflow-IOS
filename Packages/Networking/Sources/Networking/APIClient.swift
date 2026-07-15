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
/// - Resilience: safe GETs may perform one token refresh or step-up retry;
///   writes never replay automatically, including after auth failures. Safe
///   GETs may also use bounded backoff for `.verifierUnavailable` and transient
///   `URLError`s; `Retry-After` is surfaced on `429`.
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
    private let sleeper: @Sendable (Duration) async throws -> Void
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
    ///   - sleeper: cancellable delay implementation (injectable for deterministic tests).
    ///   - observationNow: monotonic time source for deterministic attempt timing.
    public init(
        baseURL: URL,
        tokenProvider: TokenProviding,
        session: URLSession = .shared,
        logger: RequestLogging? = nil,
        observer: (any APIClientObserver)? = nil,
        maxRetries: Int = 3,
        retryBaseDelay: Duration = .milliseconds(300),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
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
        self.sleeper = sleeper
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
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
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
            sleeper: sleeper,
            observationNow: observationNow
        )
    }

    // MARK: - APIClientProtocol

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let successfulAttempt = try await performRequest(
            endpoint,
            terminalTransportFailurePolicy: .mapToOffline
        )
        let (result, _): (T, HTTPURLResponse) = try decodeSuccessfulResponse(
            successfulAttempt,
            policy: endpoint.reliabilityPolicy
        )
        return result
    }

    public func sendWithServerDate<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> (T, Date?) {
        let successfulAttempt = try await performRequest(
            endpoint,
            terminalTransportFailurePolicy: .mapToOffline
        )
        let (result, http): (T, HTTPURLResponse) = try decodeSuccessfulResponse(
            successfulAttempt,
            policy: endpoint.reliabilityPolicy
        )
        return (result, Self.serverDate(from: http))
    }

    public func sendData(_ endpoint: Endpoint) async throws -> Data {
        let successfulAttempt = try await performRequest(
            endpoint,
            terminalTransportFailurePolicy: .preserveURLError
        )
        return try dataFromSuccessfulResponse(
            successfulAttempt,
            policy: endpoint.reliabilityPolicy
        )
    }

    // MARK: - Core request loop

    /// Runs the full retry/refresh loop and returns the accepted final attempt.
    /// The caller records success only after validating or decoding its body.
    private func performRequest(
        _ endpoint: Endpoint,
        terminalTransportFailurePolicy: APIClientTerminalTransportFailurePolicy
    ) async throws -> APIClientSuccessfulHTTPAttempt {
        let observationContext = observer.captureContext()
        var retryState = APIClientRetryState()
        var attemptNumber = 0
        let policy = endpoint.reliabilityPolicy
        let transientRetryLimit = maximumTransientRetryCount(for: endpoint, policy: policy)

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
                retryPlan: APIClientTransportRetryPlan(
                    backoffAttempt: retryState.backoffAttempt,
                    retryLimit: transientRetryLimit,
                    terminalFailurePolicy: terminalTransportFailurePolicy
                )
            ) {
            case let .retry(nextBackoffAttempt):
                retryState.backoffAttempt = nextBackoffAttempt
            case let .response(data, http):
                if policy.successStatusPolicy.accepts(http.statusCode) {
                    return APIClientSuccessfulHTTPAttempt(
                        data: data,
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
        retryPlan: APIClientTransportRetryPlan
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
                retryPlan: retryPlan
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
        retryPlan: APIClientTransportRetryPlan
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
        guard Self.isTransient(urlError), retryPlan.backoffAttempt < retryPlan.retryLimit else {
            recordObservation(
                request: request,
                attempt: observation.number,
                elapsed: elapsed,
                outcome: .networkFailure,
                context: observation.context
            )
            switch retryPlan.terminalFailurePolicy {
            case .mapToOffline:
                throw AppError.offline
            case .preserveURLError:
                throw urlError
            }
        }

        let nextBackoffAttempt = retryPlan.backoffAttempt + 1
        do {
            try await backoff(nextBackoffAttempt)
        } catch is CancellationError {
            recordObservation(
                request: request,
                attempt: observation.number,
                elapsed: elapsed,
                outcome: .networkFailure,
                context: observation.context
            )
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            recordObservation(
                request: request,
                attempt: observation.number,
                elapsed: elapsed,
                outcome: .networkFailure,
                context: observation.context
            )
            throw CancellationError()
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
        _ successfulAttempt: APIClientSuccessfulHTTPAttempt,
        policy: EndpointReliabilityPolicy
    ) throws -> (T, HTTPURLResponse) {
        do {
            let body: Data
            if successfulAttempt.data.isEmpty {
                guard policy.emptyBodyPolicy == .allowed else {
                    throw AppError.decoding(APIClientEmptyResponseBodyError())
                }
                body = Data("{}".utf8)
            } else {
                body = successfulAttempt.data
            }
            let decoded: T = try decode(body)
            recordObservation(
                request: successfulAttempt.request,
                observation: successfulAttempt.observation,
                outcome: .success,
                statusCode: successfulAttempt.response.statusCode
            )
            return (decoded, successfulAttempt.response)
        } catch {
            recordObservation(
                request: successfulAttempt.request,
                observation: successfulAttempt.observation,
                outcome: .decodingFailure,
                statusCode: successfulAttempt.response.statusCode
            )
            throw error
        }
    }

    private func dataFromSuccessfulResponse(
        _ successfulAttempt: APIClientSuccessfulHTTPAttempt,
        policy: EndpointReliabilityPolicy
    ) throws -> Data {
        if successfulAttempt.data.isEmpty, policy.emptyBodyPolicy == .disallowed {
            recordObservation(
                request: successfulAttempt.request,
                observation: successfulAttempt.observation,
                outcome: .decodingFailure,
                statusCode: successfulAttempt.response.statusCode
            )
            throw AppError.decoding(APIClientEmptyResponseBodyError())
        }
        recordObservation(
            request: successfulAttempt.request,
            observation: successfulAttempt.observation,
            outcome: .success,
            statusCode: successfulAttempt.response.statusCode
        )
        return successfulAttempt.data
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
           endpoint.method == .get,
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
           endpoint.method == .get,
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
           endpoint.method == .get,
           currentState.backoffAttempt < maximumTransientRetryCount(
               for: endpoint,
               policy: endpoint.reliabilityPolicy
           ) {
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
            try Task.checkCancellation()
        } catch is CancellationError {
            recordHTTPFailure(failedAttempt)
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            recordHTTPFailure(failedAttempt)
            throw CancellationError()
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
        request.timeoutInterval = endpoint.reliabilityPolicy.timeout
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

    private func maximumTransientRetryCount(
        for endpoint: Endpoint,
        policy: EndpointReliabilityPolicy
    ) -> Int {
        guard endpoint.method == .get else { return 0 }
        return min(max(0, maxRetries), policy.retryPolicy.maximumRetryCount)
    }

    private func backoff(_ attempt: Int) async throws {
        // Exponential: base * 2^(attempt-1). `attempt` is 1-based.
        let factor = 1 << (attempt - 1)
        try Task.checkCancellation()
        try await sleeper(retryBaseDelay * factor)
        try Task.checkCancellation()
    }

}
