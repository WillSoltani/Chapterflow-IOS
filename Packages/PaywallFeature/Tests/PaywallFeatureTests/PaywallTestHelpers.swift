import Testing
import Foundation
import StoreKit
import CoreKit
import Networking
@testable import PaywallFeature

// MARK: - SpyAnalyticsClient

/// Records all `track(_:)` calls for assertion in tests.
actor SpyAnalyticsClient: AnalyticsClient {
    private(set) var trackedEvents: [AnalyticsEvent] = []

    nonisolated func track(_ event: AnalyticsEvent) {
        Task { await self.append(event) }
    }

    nonisolated func beacon(_ name: String, properties: [String: String]) {}

    func flush() async {}

    private func append(_ event: AnalyticsEvent) {
        trackedEvents.append(event)
    }
}

// MARK: - StubStoreKitService

/// A minimal actor conforming to `StoreKitServicing` for use in unit tests.
/// Default protocol implementations handle the new offer-surface methods.
actor StubStoreKitService: StoreKitServicing {

    private let shouldThrowOnLoad: Bool
    private let shouldThrowOnRestore: Bool

    nonisolated let entitlementChanges: AsyncStream<Void>

    init(throwOnLoad: Bool = false, throwOnRestore: Bool = false) {
        self.shouldThrowOnLoad = throwOnLoad
        self.shouldThrowOnRestore = throwOnRestore
        self.entitlementChanges = AsyncStream { _ in }
    }

    func loadProducts() async throws -> [Product] {
        if shouldThrowOnLoad { throw StoreKitServiceError.noProductsFound }
        return []
    }

    func purchase(_ product: Product) async throws -> PurchaseResult {
        .userCancelled
    }

    func restorePurchases() async throws {
        if shouldThrowOnRestore {
            throw AppError.server(code: "restore_failed", message: "Restore failed", requestId: nil)
        }
    }

    func verifyCurrentEntitlements() async throws {}

    func currentSubscriptionStatus() async throws -> PaywallFeature.SubscriptionStatus {
        .notSubscribed
    }

    func currentTransactionID() async -> UInt64? { nil }
}
