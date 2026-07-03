import Foundation

/// The user's current subscription state as computed from StoreKit
/// `Transaction.currentEntitlements` and `Product.SubscriptionInfo.Status`.
///
/// The backend is the source of truth for entitlement gating. This enum
/// represents the *local* StoreKit view of the subscription lifecycle —
/// used for surfacing billing-related UI (grace-period warnings, billing-retry
/// banners) and for triggering backend entitlement refreshes.
public enum SubscriptionStatus: Sendable, Equatable {
    /// Status not yet determined (initial / loading state).
    case unknown
    /// No active subscription was found.
    case notSubscribed
    /// Active and in good standing.
    case subscribed(productID: String, expirationDate: Date?)
    /// Transaction is pending — Ask-to-Buy awaiting parental approval, or
    /// a payment requiring SCA (Strong Customer Authentication).
    case pending
    /// Subscription is in its grace period; payment failed but access continues
    /// temporarily while Apple retries billing.
    case inGracePeriod(productID: String, expirationDate: Date?)
    /// Apple is retrying billing; grace period has ended.
    case inBillingRetry(productID: String)
    /// Subscription was refunded and revoked by Apple.
    case revoked
    /// Subscription has expired and was not renewed.
    case expired(productID: String)

    // MARK: - Derived helpers

    /// `true` when the user should have PRO access (subscribed or in grace period).
    public var isPro: Bool {
        switch self {
        case .subscribed, .inGracePeriod: return true
        case .unknown, .notSubscribed, .pending,
             .inBillingRetry, .revoked, .expired: return false
        }
    }

    /// `true` when a billing-attention banner should be shown.
    public var requiresAttention: Bool {
        switch self {
        case .inGracePeriod, .inBillingRetry: return true
        case .unknown, .notSubscribed, .subscribed,
             .pending, .revoked, .expired: return false
        }
    }

    /// A short human-readable label suitable for a status chip.
    public var displayLabel: String {
        switch self {
        case .unknown:                    return "Loading"
        case .notSubscribed:              return "Free"
        case .subscribed:                 return "Pro"
        case .pending:                    return "Pending"
        case .inGracePeriod:              return "Grace Period"
        case .inBillingRetry:             return "Payment Issue"
        case .revoked:                    return "Revoked"
        case .expired:                    return "Expired"
        }
    }
}
