import Testing
import StoreKit
import Models
import Networking
@testable import PaywallFeature

@Suite("Paywall backend-authoritative purchase safety")
@MainActor
struct PaywallSafetyTests {
    @Test("purchase stays blocked until the backend resolves the account as free")
    func purchaseRequiresResolvedFreeEntitlement() async {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )

        await model.purchase(productID: "unexpected")

        #expect(model.entitlementResolution == .unresolved)
        #expect(!model.canPurchase)
        #expect(model.errorMessage?.contains("confirm your membership") == true)
    }

    @Test("backend free and pro responses resolve to distinct safe states")
    func backendResolutionStates() async throws {
        let freeClient = MockAPIClient()
        try await freeClient.setStub(
            entitlementResponse(plan: .free, status: nil, source: nil),
            for: "/book/me/entitlements"
        )
        let freeModel = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: freeClient
        )
        await freeModel.refreshEntitlement()
        #expect(freeModel.entitlementResolution == .resolvedFree)
        #expect(freeModel.subscriptionStatus == .notSubscribed)

        let proClient = MockAPIClient()
        try await proClient.setStub(
            entitlementResponse(plan: .pro, status: "active", source: "stripe"),
            for: "/book/me/entitlements"
        )
        let proModel = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: proClient
        )
        await proModel.refreshEntitlement()
        #expect(proModel.entitlementResolution == .resolvedPro)
        #expect(proModel.subscriptionStatus.isPro)
    }

    @Test("entitlement lookup failure blocks purchase without downgrading known Pro")
    func lookupFailureFailsClosed() async throws {
        let client = MockAPIClient()
        await client.setStub(.failure(.offline), for: "/book/me/entitlements")
        let freeModel = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: client
        )
        await freeModel.refreshEntitlement()
        #expect(freeModel.entitlementResolution == .unavailable)
        #expect(!freeModel.canPurchase)

        let proClient = MockAPIClient()
        try await proClient.setStub(
            entitlementResponse(plan: .pro, status: "active", source: "apple"),
            for: "/book/me/entitlements"
        )
        let proModel = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: proClient
        )
        await proModel.refreshEntitlement()
        await proClient.setStub(.failure(.offline), for: "/book/me/entitlements")
        await proModel.refreshEntitlement()
        #expect(proModel.entitlementResolution == .resolvedPro)
        #expect(proModel.subscriptionStatus.isPro)
    }

    @Test("restore is single-flight")
    func restoreSingleFlight() async {
        let service = SlowRestoreStoreKitService()
        let model = PaywallModel(
            storeKitService: service,
            apiClient: MockAPIClient()
        )
        let started = Task {
            for await _ in service.restoreStarted { return }
        }
        let firstRestore = Task { await model.restorePurchases() }
        await started.value

        await model.restorePurchases()
        #expect(await service.restoreCallCount() == 1)

        await service.finishRestore()
        await firstRestore.value
    }

    private func entitlementResponse(
        plan: Entitlement.Plan,
        status: String?,
        source: String?
    ) -> EntitlementResponse {
        EntitlementResponse(
            entitlement: Entitlement(
                plan: plan,
                proStatus: status,
                proSource: source,
                freeBookSlots: 2,
                unlockedBookIds: [],
                unlockedBooksCount: 0,
                remainingFreeStarts: 1,
                currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil,
                licenseKey: nil,
                licenseExpiresAt: nil
            ),
            paywall: nil
        )
    }
}

private actor SlowRestoreStoreKitService: StoreKitServicing {
    nonisolated let restoreStarted: AsyncStream<Void>
    private let restoreStartedContinuation: AsyncStream<Void>.Continuation
    private var restoreContinuation: CheckedContinuation<Void, Never>?
    private var restoreCalls = 0

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        restoreStarted = stream
        restoreStartedContinuation = continuation
    }

    func entitlementChanges() async -> AsyncStream<Void> { AsyncStream { _ in } }
    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }

    func restorePurchases() async {
        restoreCalls += 1
        restoreStartedContinuation.yield(())
        await withCheckedContinuation { restoreContinuation = $0 }
    }

    func finishRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }

    func restoreCallCount() -> Int { restoreCalls }
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> PaywallFeature.SubscriptionStatus { .notSubscribed }
    func currentTransactionID() async -> UInt64? { nil }
}
