import Foundation

/// One privacy-safe record for one actual API network attempt.
///
/// Construction closes every free-form field: the method and outcomes are
/// enums, the route is sanitized, scalar values are bounded, and request IDs
/// accept only a short ASCII correlation format.
public struct APIRequestObservation: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case put = "PUT"
        case delete = "DELETE"
        case unknown = "UNKNOWN"

        public init(_ value: String?) {
            guard let value else {
                self = .unknown
                return
            }

            switch value {
            case "GET", "get": self = .get
            case "POST", "post": self = .post
            case "PATCH", "patch": self = .patch
            case "PUT", "put": self = .put
            case "DELETE", "delete": self = .delete
            default: self = .unknown
            }
        }
    }

    public enum Outcome: String, Sendable {
        case success
        case httpFailure = "http_failure"
        case networkFailure = "network_failure"
        case decodingFailure = "decoding_failure"
        case cancellation
    }

    /// Whether the client selected another attempt or this attempt is terminal.
    public enum RetryDisposition: String, Sendable {
        case final
        case willRetry = "will_retry"
    }

    public let method: Method
    public let route: String
    public let attempt: Int
    public let elapsed: Duration
    public let outcome: Outcome
    public let statusCode: Int?
    public let requestId: String?
    public let retryDisposition: RetryDisposition

    public init(
        method: Method,
        route: String,
        attempt: Int,
        elapsed: Duration,
        outcome: Outcome,
        statusCode: Int?,
        requestId: String?,
        retryDisposition: RetryDisposition
    ) {
        self.method = method
        self.route = APIRouteSanitizer.sanitize(route)
        self.attempt = min(max(attempt, 1), 999)
        self.elapsed = min(max(elapsed, .zero), .seconds(3_600))
        self.outcome = outcome
        self.statusCode = statusCode.flatMap { (100...599).contains($0) ? $0 : nil }
        self.requestId = Self.safeRequestId(requestId)
        self.retryDisposition = retryDisposition
    }

    private static func safeRequestId(_ requestId: String?) -> String? {
        let prefix = "req-"
        guard let requestId, requestId.hasPrefix(prefix) else { return nil }

        let identifier = requestId.dropFirst(prefix.count)
        guard (16...48).contains(identifier.utf8.count) else { return nil }

        var hasNumber = false
        var hasNonHexLetter = false
        for byte in identifier.utf8 {
            if (48...57).contains(byte) {
                hasNumber = true
            } else if (103...122).contains(byte) {
                hasNonHexLetter = true
            } else if !(97...102).contains(byte) {
                return nil
            }
        }

        return hasNumber && hasNonHexLetter ? requestId : nil
    }
}
