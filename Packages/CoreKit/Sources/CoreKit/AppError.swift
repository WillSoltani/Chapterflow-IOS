import Foundation

/// The canonical error type for the entire app.
///
/// Every layer maps its failures into `AppError` so that UI code has a single,
/// exhaustive set of cases to render (via a shared `ErrorView`/`Toast`).
/// `Networking` maps the API error envelope
/// (`{"error":{"code","message","requestId"}}`) into `.server` (or a more
/// specific case based on HTTP status), and decoding failures into `.decoding`.
public enum AppError: Error, LocalizedError {
    /// No valid session/token is present; the user must sign in.
    case unauthenticated
    /// The session exists but requires a fresh re-authentication (e.g. a
    /// security-sensitive action, or a refresh token that can no longer renew).
    case reauthRequired
    /// A required app-integrity / attestation verifier is unavailable.
    case verifierUnavailable
    /// The server rate-limited the request. `retryAfter` is the suggested wait
    /// in seconds, when the server provides a `Retry-After` header.
    case rateLimited(retryAfter: TimeInterval?)
    /// The authenticated user is not allowed to perform this action (HTTP 403).
    case forbidden
    /// The device has no usable network connection.
    case offline
    /// The request was rejected as malformed/invalid; the associated value is a
    /// user-facing explanation.
    case invalidInput(String)
    /// The requested resource does not exist (HTTP 404).
    case notFound
    /// A structured server error decoded from the error envelope.
    case server(code: String, message: String, requestId: String?)
    /// A response body could not be decoded into the expected model.
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You're signed out. Please sign in to continue."
        case .reauthRequired:
            return "For your security, please sign in again to continue."
        case .verifierUnavailable:
            return "We couldn't verify this device right now. Please try again in a moment."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds > 0 {
                return "You're going a little fast. Try again in \(Int(seconds.rounded(.up))) seconds."
            }
            return "You're going a little fast. Please try again in a moment."
        case .forbidden:
            return "You don't have access to this."
        case .offline:
            return "You're offline. Check your connection and try again."
        case .invalidInput(let message):
            return message
        case .notFound:
            return "We couldn't find what you were looking for."
        case .server(_, let message, _):
            // Prefer the server's human message when present; fall back otherwise.
            return message.isEmpty ? "Something went wrong on our end. Please try again." : message
        case .decoding:
            return "We received something unexpected. Please try again."
        }
    }

    /// A short, machine-friendly identifier for the case, handy for logging and
    /// analytics without leaking the (possibly PII-laden) message.
    public var code: String {
        switch self {
        case .unauthenticated: return "unauthenticated"
        case .reauthRequired: return "reauth_required"
        case .verifierUnavailable: return "verifier_unavailable"
        case .rateLimited: return "rate_limited"
        case .forbidden: return "forbidden"
        case .offline: return "offline"
        case .invalidInput: return "invalid_input"
        case .notFound: return "not_found"
        case .server(let code, _, _): return code.isEmpty ? "server" : code
        case .decoding: return "decoding"
        }
    }

    /// Whether this error indicates the user should be routed back to sign-in.
    public var isAuthenticationFailure: Bool {
        switch self {
        case .unauthenticated, .reauthRequired: return true
        default: return false
        }
    }

    /// Whether retrying the same request could plausibly succeed later.
    public var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited, .verifierUnavailable: return true
        case .server: return true
        default: return false
        }
    }
}

// `AppError` is safe to pass across concurrency domains. The only non-`Sendable`
// payload is the `Error` carried by `.decoding`, which in practice is an
// immutable value (`DecodingError`) captured at the failure site and never
// mutated thereafter.
extension AppError: @unchecked Sendable {}
