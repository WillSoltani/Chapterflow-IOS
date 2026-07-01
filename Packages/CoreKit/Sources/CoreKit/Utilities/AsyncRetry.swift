import Foundation

/// Runs an async operation with exponential backoff, retrying transient failures.
///
/// The delay grows by `multiplier` each attempt. When the thrown error is an
/// `AppError.rateLimited(retryAfter:)` carrying a concrete wait, that server-
/// provided delay is honored instead of the computed backoff. `shouldRetry`
/// lets callers restrict which errors are worth retrying (defaults to
/// `AppError.isRetryable`, falling back to retrying unknown errors).
///
/// - Parameters:
///   - maxAttempts: Total attempts including the first (must be ≥ 1).
///   - initialDelay: Delay before the second attempt.
///   - multiplier: Backoff growth factor applied after each failure.
///   - shouldRetry: Predicate deciding whether a given error is retryable.
///   - operation: The work to perform; retried on failure.
/// - Returns: The operation's successful value.
/// - Throws: The last error if all attempts fail (or the error is non-retryable).
public func withAsyncRetry<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelay: Duration = .milliseconds(300),
    multiplier: Double = 2.0,
    shouldRetry: @Sendable (Error) -> Bool = { ($0 as? AppError)?.isRetryable ?? true },
    operation: @Sendable () async throws -> T
) async throws -> T {
    precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
    var attempt = 1
    var delay = initialDelay

    while true {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard attempt < maxAttempts, shouldRetry(error) else {
                throw error
            }
            let wait: Duration
            if case AppError.rateLimited(let retryAfter?) = error, retryAfter > 0 {
                wait = .seconds(retryAfter)
            } else {
                wait = delay
            }
            try await Task.sleep(for: wait)
            attempt += 1
            delay = delay * multiplier
        }
    }
}
