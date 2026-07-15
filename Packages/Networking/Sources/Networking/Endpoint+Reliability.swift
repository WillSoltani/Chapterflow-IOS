import Foundation

/// The bounded transport behavior an ``Endpoint`` permits.
///
/// Writes intentionally have no automatic replay, including after auth or
/// transient failures. A future package may add keyed-write retry only after
/// the backend defines and implements the complete idempotency contract; this
/// policy does not send an idempotency key.
public struct EndpointReliabilityPolicy: Sendable, Equatable {
    public enum RetryPolicy: Sendable, Equatable {
        case none
        case boundedTransientRead(maxRetries: Int)

        var maximumRetryCount: Int {
            switch self {
            case .none:
                return 0
            case let .boundedTransientRead(maxRetries):
                return max(0, maxRetries)
            }
        }
    }

    public enum SuccessStatusPolicy: Sendable, Equatable {
        case successfulResponses
        case exact(Set<Int>)

        func accepts(_ statusCode: Int) -> Bool {
            switch self {
            case .successfulResponses:
                return (200..<300).contains(statusCode)
            case let .exact(statusCodes):
                return statusCodes.contains(statusCode)
            }
        }
    }

    public enum EmptyBodyPolicy: Sendable, Equatable {
        case disallowed
        case allowed
    }

    public let timeout: TimeInterval
    public let retryPolicy: RetryPolicy
    public let successStatusPolicy: SuccessStatusPolicy
    public let emptyBodyPolicy: EmptyBodyPolicy

    public init(
        timeout: TimeInterval = 60,
        retryPolicy: RetryPolicy,
        successStatusPolicy: SuccessStatusPolicy = .successfulResponses,
        emptyBodyPolicy: EmptyBodyPolicy = .disallowed
    ) {
        self.timeout = timeout.isFinite && timeout > 0 ? timeout : 60
        self.retryPolicy = retryPolicy
        self.successStatusPolicy = successStatusPolicy
        self.emptyBodyPolicy = emptyBodyPolicy
    }
}

public extension Endpoint {
    /// The resolved policy. Assigning an override is intentionally explicit;
    /// existing endpoint call sites continue using method-based defaults.
    var reliabilityPolicy: EndpointReliabilityPolicy {
        get {
            if let reliabilityPolicyOverride {
                return reliabilityPolicyOverride
            }
            switch method {
            case .get:
                return EndpointReliabilityPolicy(
                    retryPolicy: .boundedTransientRead(maxRetries: 3)
                )
            case .post, .patch, .put, .delete:
                return EndpointReliabilityPolicy(retryPolicy: .none)
            }
        }
        set {
            reliabilityPolicyOverride = newValue
        }
    }
}
