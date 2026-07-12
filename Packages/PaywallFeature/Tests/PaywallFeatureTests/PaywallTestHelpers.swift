import Testing
import Foundation
import StoreKit
import CoreKit
import Networking
@testable import PaywallFeature

let storeKitTestAccountSubject = "00000000-0000-4000-8000-000000000111"

func storeKitTestAccountToken() throws -> UUID {
    try #require(UUID(uuidString: storeKitTestAccountSubject))
}

@discardableResult
func activateStoreKitTestAccount(_ service: StoreKitService) throws -> UUID {
    let token = try storeKitTestAccountToken()
    #expect(service.activateAccount(authenticatedSubject: storeKitTestAccountSubject))
    return token
}

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

    enum LoadFailure: Sendable {
        case none
        case noProducts
        case invalidConfiguration
        case offline
        case storeKitNetwork
        case cancelled
    }

    private let loadFailure: LoadFailure
    private let shouldThrowOnRestore: Bool

    init(
        throwOnLoad: Bool = false,
        throwOnRestore: Bool = false,
        loadFailure: LoadFailure = .none
    ) {
        self.loadFailure = throwOnLoad ? .noProducts : loadFailure
        self.shouldThrowOnRestore = throwOnRestore
    }

    func entitlementChanges() async -> AsyncStream<Void> { AsyncStream { _ in } }

    func loadProducts() async throws -> [Product] {
        switch loadFailure {
        case .none:
            return []
        case .noProducts:
            throw StoreKitServiceError.noProductsFound
        case .invalidConfiguration:
            throw StoreKitServiceError.invalidConfiguration
        case .offline:
            throw AppError.offline
        case .storeKitNetwork:
            throw StoreKitError.networkError(URLError(.notConnectedToInternet))
        case .cancelled:
            throw CancellationError()
        }
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

// MARK: - SlowEmptyStoreKitService

/// Suspends product loading so tests can prove repeated requests remain
/// single-flight while the first StoreKit operation is in progress.
actor SlowEmptyStoreKitService: StoreKitServicing {
    nonisolated let loadStarted: AsyncStream<Void>
    private let loadStartedContinuation: AsyncStream<Void>.Continuation
    private var pendingLoad: CheckedContinuation<Void, Never>?
    private var calls = 0

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        loadStarted = stream
        loadStartedContinuation = continuation
    }

    func entitlementChanges() async -> AsyncStream<Void> { AsyncStream { _ in } }

    func loadProducts() async throws -> [Product] {
        calls += 1
        loadStartedContinuation.yield(())
        await withCheckedContinuation { pendingLoad = $0 }
        return []
    }

    func finishLoad() {
        pendingLoad?.resume()
        pendingLoad = nil
    }

    func loadCallCount() -> Int { calls }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> PaywallFeature.SubscriptionStatus { .notSubscribed }
    func currentTransactionID() async -> UInt64? { nil }
}
