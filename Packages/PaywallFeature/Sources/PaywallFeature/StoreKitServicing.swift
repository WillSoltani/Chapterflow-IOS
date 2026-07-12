import Foundation
import StoreKit

/// The outcome of a ``StoreKitService/purchase(_:)`` call.
public enum PurchaseResult: Sendable, Equatable {
    /// The transaction was verified, authoritatively processed and finished,
    /// and the returned backend entitlement remained active Pro. The source is
    /// carried through verbatim so the UI never guesses that Apple won source
    /// precedence over an existing promo, admin, license, or gift entitlement.
    case purchased(proSource: String?)
    /// The purchase is deferred (Ask to Buy awaiting approval, or SCA).
    case pending
    /// The user cancelled the purchase sheet.
    case userCancelled
}

/// Errors specific to ``StoreKitService`` that are not covered by `AppError`.
public enum StoreKitServiceError: Error, LocalizedError, Sendable {
    case invalidConfiguration
    case productNotConfigured
    case unverified(Error)
    case noProductsFound
    case accountBindingUnavailable
    case accountBindingMismatch
    case accountChangedDuringVerification
    case unsupportedOwnership
    case transactionNotActive
    case processedWithoutActiveEntitlement

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Subscriptions are not configured for this build. Please contact support."
        case .productNotConfigured:
            return "This subscription is not available in this build. Please contact support."
        case .unverified:
            return "The purchase could not be verified. Please contact support."
        case .noProductsFound:
            return "Subscription products are unavailable right now. Please try again later."
        case .accountBindingUnavailable:
            return "Please sign in again before managing subscriptions."
        case .accountBindingMismatch:
            return "This purchase belongs to a different ChapterFlow account."
        case .accountChangedDuringVerification:
            return "Your account changed while the purchase was being confirmed."
        case .unsupportedOwnership:
            return "This subscription ownership type is not supported."
        case .transactionNotActive:
            return "This subscription is no longer active."
        case .processedWithoutActiveEntitlement:
            return "The purchase was processed, but active access could not be confirmed."
        }
    }
}

/// StoreKit boundary used by paywall and entitlement models.
public protocol StoreKitServicing: Sendable {
    func entitlementChanges() async -> AsyncStream<Void>
    func loadProducts() async throws -> [Product]
    func purchase(_ product: Product) async throws -> PurchaseResult
    func restorePurchases() async throws
    func currentSubscriptionStatus() async throws -> SubscriptionStatus
    func verifyCurrentEntitlements() async throws
    func verifyUnfinishedTransactions() async throws
    func currentTransactionID() async -> UInt64?
    func introOfferEligibleProductIDs() async -> Set<String>
    func winBackDisplayInfo() async -> WinBackDisplayInfo?
    func purchaseWithWinBack(productID: String, offerID: String) async throws -> PurchaseResult
}

/// Defaults keep previews and focused test doubles small.
public extension StoreKitServicing {
    func introOfferEligibleProductIDs() async -> Set<String> { [] }
    func winBackDisplayInfo() async -> WinBackDisplayInfo? { nil }
    func purchaseWithWinBack(productID: String, offerID: String) async throws -> PurchaseResult {
        .userCancelled
    }
    func verifyUnfinishedTransactions() async throws {}
}

typealias StoreKitTransactionListenerTaskFactory = @Sendable (
    @escaping @Sendable (VerificationResult<Transaction>) async -> Void
) -> Task<Void, Never>
