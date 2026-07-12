/// The in-flight state of a purchase initiated from the paywall.
public enum PurchaseState: Sendable, Equatable {
    case idle
    case purchasing
    case restoring
    /// A deferred purchase (Ask-to-Buy) is waiting for parental approval.
    case pendingApproval
    /// An externally initiated transaction is waiting for an entitlement read.
    /// Direct `.purchased(proSource:)` results skip this state because the
    /// service contract
    /// already includes an active backend Apple Pro acknowledgement.
    case confirmingAccess
    /// Purchase completed after an authoritative backend Apple Pro acknowledgement.
    case success(productID: String)
    /// A safe, user-facing failure message.
    case failed(String)

    public var isInProgress: Bool {
        switch self {
        case .purchasing, .restoring, .pendingApproval, .confirmingAccess:
            return true
        case .idle, .success, .failed:
            return false
        }
    }

    var permitsNewBillingAction: Bool {
        switch self {
        case .idle, .failed:
            return true
        case .purchasing, .restoring, .pendingApproval, .confirmingAccess, .success:
            return false
        }
    }
}

/// The operation that currently owns the paywall's billing interaction.
///
/// `PurchaseState` remains the user-visible lifecycle, while this narrower
/// state serializes mutually exclusive entry points.
enum BillingAction: Sendable, Equatable {
    case purchase
    case winBack
    case restore
}

/// Whether the backend has authoritatively resolved the account's current plan.
public enum EntitlementResolutionState: Sendable, Equatable {
    case unresolved
    case resolving
    case resolvedFree
    case resolvedPro
    case unavailable

    public var permitsPurchase: Bool {
        self == .resolvedFree
    }
}
