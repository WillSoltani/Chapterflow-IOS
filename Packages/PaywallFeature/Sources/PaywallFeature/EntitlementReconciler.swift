import Foundation
import Models

/// Pure, stateless logic for cross-platform entitlement reconciliation.
///
/// Compares the backend entitlement (always the gating authority) with local
/// StoreKit state and decides what — if anything — the service must do to keep
/// the two in sync.
///
/// The reconciler is completely decoupled from StoreKit and networking,
/// so it is fast, deterministic, and trivially unit-testable.
public struct EntitlementReconciler: Sendable {

    // MARK: - Action

    /// The action the service should take after comparing backend and StoreKit state.
    public enum Action: Equatable, Sendable {
        /// Backend is authoritative and current. No further action needed.
        case useBackend
        /// StoreKit shows an active Apple subscription the backend hasn't processed yet.
        /// The caller should re-post the transaction JWS to
        /// `POST /book/me/billing/apple/verify`, then re-fetch the backend entitlement.
        case triggerAppleVerify(productIds: Set<String>)
    }

    public init() {}

    // MARK: - Reconcile

    /// Reconciles backend and StoreKit entitlement state.
    ///
    /// Rules (backend always controls gating):
    /// - No configured Apple product is active in StoreKit → `.useBackend`.
    /// - Backend is Pro **and** StoreKit expiry ≤ backend period end → `.useBackend`
    ///   (backend already reflects the active Apple subscription).
    /// - Backend is Pro **and** StoreKit expiry > backend period end → `.triggerAppleVerify`
    ///   (StoreKit processed a renewal before the backend webhook fired).
    /// - Backend is free/non-pro **and** StoreKit shows an active Apple subscription
    ///   → `.triggerAppleVerify` (purchase or restore not yet processed by backend).
    ///
    /// - Parameters:
    ///   - backend: Latest `Entitlement` from `GET /book/me/entitlements`.
    ///   - storeKitActiveProductIds: Set of product IDs with currently active
    ///     StoreKit entitlements (subscribed or in grace period).
    ///   - storeKitLatestExpiryDate: Latest expiry date among active Apple subscriptions.
    ///     `nil` when not available (non-renewing product or unknown).
    ///   - backendPeriodEndDate: Parsed `Entitlement.currentPeriodEnd`; `nil` if absent.
    ///   - knownAppleProductIds: The set of Apple subscription product IDs configured
    ///     for this app (from `StoreKitConfig.allProductIDs`).
    public func reconcile(
        backend: Entitlement,
        storeKitActiveProductIds: Set<String>,
        storeKitLatestExpiryDate: Date?,
        backendPeriodEndDate: Date?,
        knownAppleProductIds: Set<String>
    ) -> Action {
        let backendIsPro = backend.plan == .pro && backend.proStatus == "active"
        let activeAppleProductIds = storeKitActiveProductIds.intersection(knownAppleProductIds)

        guard !activeAppleProductIds.isEmpty else {
            return .useBackend
        }

        if backendIsPro {
            // Backend already reflects Pro. Only re-verify when StoreKit expiry is later,
            // meaning a renewal was processed locally before the backend webhook fired.
            if let storeKitExpiry = storeKitLatestExpiryDate,
               let backendEnd = backendPeriodEndDate,
               storeKitExpiry > backendEnd {
                return .triggerAppleVerify(productIds: activeAppleProductIds)
            }
            return .useBackend
        }

        // Backend says free/non-pro, but StoreKit has an active Apple subscription.
        // The transaction hasn't been processed by the backend yet.
        return .triggerAppleVerify(productIds: activeAppleProductIds)
    }
}

// MARK: - SubscriptionStatus → reconciler inputs

extension SubscriptionStatus {
    /// Product ID and expiry date from the active Apple subscription, if any.
    /// Grace period subscriptions are included (user still has access).
    var activeAppleEntitlement: (productID: String, expiryDate: Date?)? {
        switch self {
        case .subscribed(let id, let exp):    return (id, exp)
        case .inGracePeriod(let id, let exp): return (id, exp)
        default:                              return nil
        }
    }

    /// Single-item set of the active product ID, or empty when not active.
    var activeProductIds: Set<String> {
        guard let info = activeAppleEntitlement else { return [] }
        return [info.productID]
    }

    /// Latest expiry date, or `nil` when not available.
    var latestExpiryDate: Date? {
        activeAppleEntitlement?.expiryDate
    }
}
