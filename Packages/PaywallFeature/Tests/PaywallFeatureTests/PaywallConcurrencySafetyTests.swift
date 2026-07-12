import Foundation
import StoreKit
import Testing
import CoreKit
import Models
import Networking
@testable import PaywallFeature

private typealias SubscriptionStatus = PaywallFeature.SubscriptionStatus

@Suite("Paywall concurrency safety")
@MainActor
struct PaywallConcurrencySafetyTests {
    @Test("cancelled product load cannot commit when the dependency ignores cancellation")
    func cancelledProductLoadDoesNotCommit() async {
        let storeKit = ControlledStoreKitService()
        let model = PaywallModel(storeKitService: storeKit, apiClient: MockAPIClient())
        let load = Task { await model.loadProducts() }
        await storeKit.waitForLoadStart()

        #expect(model.productAvailability == .loading)
        load.cancel()
        await storeKit.finishProductLoad()
        await load.value

        #expect(model.productAvailability == .idle)
        #expect(model.productInfos.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoadingProducts)
    }

    @Test("newer entitlement response wins when an older response completes last")
    func staleEntitlementResponseCannotCommit() async {
        let client = SequencedEntitlementAPIClient()
        let storeKit = ControlledStoreKitService(status: .notSubscribed)
        let model = PaywallModel(storeKitService: storeKit, apiClient: client)

        let olderRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(1)
        let newerRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(2)

        await client.succeedRequest(2, with: entitlementResponse(plan: .free))
        await newerRefresh.value
        await client.succeedRequest(
            1,
            with: entitlementResponse(plan: .pro, status: "active", source: "apple")
        )
        await olderRefresh.value

        #expect(model.entitlementResolution == .resolvedFree)
        #expect(model.subscriptionStatus == .notSubscribed)
    }

    @Test("cancelled latest refresh restores the last stable resolution")
    func cancelledRefreshRestoresStableResolution() async {
        let client = SequencedEntitlementAPIClient()
        let storeKit = ControlledStoreKitService(status: .notSubscribed)
        let model = PaywallModel(storeKitService: storeKit, apiClient: client)

        let initialRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(1)
        await client.succeedRequest(1, with: entitlementResponse(plan: .free))
        await initialRefresh.value
        #expect(model.entitlementResolution == .resolvedFree)

        let cancelledRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(2)
        cancelledRefresh.cancel()
        await client.succeedRequest(
            2,
            with: entitlementResponse(plan: .pro, status: "active", source: "apple")
        )
        await cancelledRefresh.value

        #expect(model.entitlementResolution == .resolvedFree)
        #expect(model.subscriptionStatus == .notSubscribed)
    }

    @Test("overlapping cancelled refresh cannot strand membership as resolving")
    func overlappingCancellationDoesNotStrandResolving() async {
        let client = SequencedEntitlementAPIClient()
        let storeKit = ControlledStoreKitService(status: .notSubscribed)
        let model = PaywallModel(storeKitService: storeKit, apiClient: client)

        let olderRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(1)
        let cancelledRefresh = Task { await model.refreshEntitlement() }
        await client.waitForRequestCount(2)

        cancelledRefresh.cancel()
        await client.succeedRequest(2, with: entitlementResponse(plan: .free))
        await cancelledRefresh.value
        await client.succeedRequest(
            1,
            with: entitlementResponse(plan: .pro, status: "active", source: "apple")
        )
        await olderRefresh.value

        #expect(model.entitlementResolution == .unresolved)
        #expect(model.entitlementResolution != .resolving)
    }

    @Test("backend Pro preserves StoreKit billing-retry lifecycle")
    func backendProPreservesBillingRetry() async throws {
        let client = MockAPIClient()
        try await client.setStub(
            entitlementResponse(plan: .pro, status: "active", source: "apple"),
            for: "/book/me/entitlements"
        )
        let storeKit = ControlledStoreKitService(
            status: .inBillingRetry(productID: "com.chapterflow.pro.monthly")
        )
        let model = PaywallModel(storeKitService: storeKit, apiClient: client)

        await model.refreshEntitlement()

        #expect(model.entitlementResolution == .resolvedPro)
        #expect(
            model.subscriptionStatus == .inBillingRetry(
                productID: "com.chapterflow.pro.monthly"
            )
        )
    }

    @Test(
        "purchased result is authoritative across a stale entitlement read",
        arguments: [PaywallFeature.SubscriptionStatus.notSubscribed, .unknown]
    )
    func purchasedResultSurvivesStaleFreeRead(
        storeStatus: PaywallFeature.SubscriptionStatus
    ) async throws {
        let client = MockAPIClient()
        try await client.setStub(
            entitlementResponse(plan: .free),
            for: "/book/me/entitlements"
        )
        let model = PaywallModel(
            storeKitService: ControlledStoreKitService(status: storeStatus),
            apiClient: client
        )
        model.inject(
            productInfos: [],
            status: .notSubscribed,
            entitlementResolution: .resolvedFree
        )

        model.handlePurchaseResult(
            .purchased(proSource: "apple"),
            productID: "com.chapterflow.pro.monthly"
        )

        #expect(
            model.purchaseState
                == .success(productID: "com.chapterflow.pro.monthly")
        )
        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "apple")
        #expect(!model.canPurchase)
        #expect(await client.recordedEndpoints.isEmpty)

        await model.refreshEntitlement()

        #expect(
            model.purchaseState
                == .success(productID: "com.chapterflow.pro.monthly")
        )
        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "apple")
        #expect(!model.canPurchase)

        try await client.setStub(
            entitlementResponse(plan: .pro, status: "active", source: "apple"),
            for: "/book/me/entitlements"
        )
        await model.refreshEntitlement()
        try await client.setStub(
            entitlementResponse(plan: .free),
            for: "/book/me/entitlements"
        )
        await model.refreshEntitlement()

        #expect(model.purchaseState == .idle)
        #expect(model.entitlementResolution == .resolvedFree)
        #expect(model.subscriptionStatus == .notSubscribed)
    }

    @Test("processed purchase preserves an authoritative admin source")
    func purchasedResultPreservesAdminSource() async throws {
        let client = MockAPIClient()
        try await client.setStub(
            entitlementResponse(plan: .free),
            for: "/book/me/entitlements"
        )
        let model = PaywallModel(
            storeKitService: ControlledStoreKitService(status: .notSubscribed),
            apiClient: client
        )
        model.inject(
            productInfos: [],
            status: .notSubscribed,
            entitlementResolution: .resolvedFree
        )

        model.handlePurchaseResult(
            .purchased(proSource: "admin"),
            productID: "com.chapterflow.pro.monthly"
        )

        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "admin")
        await model.refreshEntitlement()
        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "admin")

        try await client.setStub(
            entitlementResponse(plan: .pro, status: "active", source: "admin"),
            for: "/book/me/entitlements"
        )
        await model.refreshEntitlement()

        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "admin")
    }

    @Test(
        "explicit ended StoreKit state overrides purchased-grant readback",
        arguments: [
            PaywallFeature.SubscriptionStatus.revoked,
            PaywallFeature.SubscriptionStatus.expired(
                productID: "com.chapterflow.pro.monthly"
            )
        ]
    )
    func endedStoreKitStateOverridesPurchasedGrant(
        status: PaywallFeature.SubscriptionStatus
    ) async throws {
        let client = MockAPIClient()
        try await client.setStub(
            entitlementResponse(plan: .free),
            for: "/book/me/entitlements"
        )
        let model = PaywallModel(
            storeKitService: ControlledStoreKitService(status: status),
            apiClient: client
        )
        model.inject(
            productInfos: [],
            status: .notSubscribed,
            entitlementResolution: .resolvedFree
        )
        model.handlePurchaseResult(
            .purchased(proSource: "apple"),
            productID: "com.chapterflow.pro.monthly"
        )

        await model.refreshEntitlement()

        #expect(model.purchaseState == .idle)
        #expect(model.entitlementResolution == .resolvedFree)
        #expect(model.subscriptionStatus == status)
        #expect(model.subscriptionStatus.isLapsed)
        #expect(model.proSource == nil)
    }

    @Test("win-back purchased result commits success without a follow-up GET")
    func winBackPurchasedResultIsAuthoritative() async {
        let client = MockAPIClient()
        let storeKit = ControlledStoreKitService(
            status: .notSubscribed,
            winBackResult: .purchased(proSource: "apple")
        )
        let model = PaywallModel(storeKitService: storeKit, apiClient: client)
        model.inject(
            productInfos: [],
            status: .expired(productID: "com.chapterflow.pro.annual"),
            entitlementResolution: .resolvedFree,
            winBackDisplay: WinBackDisplayInfo(
                productID: "com.chapterflow.pro.annual",
                productDisplayName: "Annual Pro",
                offerDisplayPrice: "Free",
                offerPeriodText: "7 days",
                regularDisplayPrice: "$49.99",
                regularPeriodLabel: "year",
                paymentMode: .freeTrial,
                offerID: "win-back"
            )
        )

        await model.purchaseWinBack()

        #expect(await storeKit.winBackPurchaseCount() == 1)
        #expect(
            model.purchaseState
                == .success(productID: "com.chapterflow.pro.annual")
        )
        #expect(model.entitlementResolution == .resolvedPro)
        #expect(model.proSource == "apple")
        #expect(await client.recordedEndpoints.isEmpty)
    }

}

@Suite("Subscription management error safety")
@MainActor
struct SubscriptionManagementErrorSafetyTests {
    @Test("cancelled refresh preserves prior state without presenting failure")
    func cancelledRefreshIsNotFailure() async {
        let client = SequencedEntitlementAPIClient()
        let storeKit = ControlledStoreKitService(
            status: .subscribed(productID: "com.chapterflow.pro.annual", expirationDate: nil),
            transactionID: 42
        )
        let model = SubscriptionManagementModel(
            storeKitService: storeKit,
            apiClient: client
        )
        let refresh = Task { await model.refresh() }
        await client.waitForRequestCount(1)

        refresh.cancel()
        await client.succeedRequest(
            1,
            with: entitlementResponse(plan: .pro, status: "active", source: "apple")
        )
        await refresh.value

        #expect(model.detailState == .free)
        #expect(model.activeTransactionID == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test("arbitrary and server errors map to allowlisted codes and copy")
    func errorsAreRedacted() {
        let sensitive = SensitiveTestError()
        let outcome = SubscriptionManagementModel.safeRefundFailureOutcome(for: sensitive)
        guard case .failed(let message) = outcome else {
            Issue.record("Expected a safe failed refund outcome")
            return
        }

        #expect(message == "We couldn't submit the refund request. Please try again.")
        #expect(!message.contains(SensitiveTestError.secret))
        #expect(
            SubscriptionManagementModel.safeErrorCode(for: sensitive)
                == "subscription_operation_failed"
        )

        let serverError = AppError.server(
            code: SensitiveTestError.secret,
            message: SensitiveTestError.secret,
            requestId: SensitiveTestError.secret
        )
        #expect(SubscriptionManagementModel.safeErrorCode(for: serverError) == "server")
    }

    @Test("cancellation maps to a nonfailure refund outcome")
    func refundCancellationIsNonfailure() {
        #expect(
            SubscriptionManagementModel.safeRefundFailureOutcome(for: CancellationError())
                == .userCancelled
        )
        #expect(
            SubscriptionManagementModel.safeErrorCode(for: CancellationError())
                == "cancelled"
        )
    }
}

private actor ControlledStoreKitService: StoreKitServicing {
    private var status: SubscriptionStatus
    private let transactionID: UInt64?
    private var pendingProductLoad: CheckedContinuation<[Product], Never>?
    private var productLoadStarted = false
    private var productLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var restores = 0
    private var winBackPurchases = 0
    private let winBackResult: PurchaseResult

    init(
        status: SubscriptionStatus = .notSubscribed,
        transactionID: UInt64? = nil,
        winBackResult: PurchaseResult = .userCancelled
    ) {
        self.status = status
        self.transactionID = transactionID
        self.winBackResult = winBackResult
    }

    func entitlementChanges() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func loadProducts() async throws -> [Product] {
        productLoadStarted = true
        for waiter in productLoadWaiters {
            waiter.resume()
        }
        productLoadWaiters.removeAll()
        return await withCheckedContinuation { pendingProductLoad = $0 }
    }

    func waitForLoadStart() async {
        guard !productLoadStarted else { return }
        await withCheckedContinuation { productLoadWaiters.append($0) }
    }

    func finishProductLoad() {
        pendingProductLoad?.resume(returning: [])
        pendingProductLoad = nil
    }

    func purchase(_ product: Product) async throws -> PurchaseResult {
        .userCancelled
    }

    func restorePurchases() async throws {
        restores += 1
    }

    func verifyCurrentEntitlements() async throws {}

    func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        status
    }

    func currentTransactionID() async -> UInt64? {
        transactionID
    }

    func purchaseWithWinBack(
        productID: String,
        offerID: String
    ) async throws -> PurchaseResult {
        winBackPurchases += 1
        return winBackResult
    }

    func restoreCount() -> Int { restores }
    func winBackPurchaseCount() -> Int { winBackPurchases }
}

private actor SequencedEntitlementAPIClient: APIClientProtocol {
    private var nextRequestID = 1
    private var pending: [
        Int: CheckedContinuation<EntitlementResponse, any Error>
    ] = [:]
    private var requestCount = 0
    private var requestCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        guard endpoint.path == "/book/me/entitlements" else {
            throw AppError.notFound
        }
        let requestID = nextRequestID
        nextRequestID += 1
        requestCount += 1
        resumeRequestCountWaiters()

        let response = try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
        }
        guard let typedResponse = response as? T else {
            throw SequencedClientError.unexpectedResponseType
        }
        return typedResponse
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard requestCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeedRequest(_ requestID: Int, with response: EntitlementResponse) {
        pending.removeValue(forKey: requestID)?.resume(returning: response)
    }

    private func resumeRequestCountWaiters() {
        let satisfiedCounts = requestCountWaiters.keys.filter { $0 <= requestCount }
        for count in satisfiedCounts {
            let waiters = requestCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private enum SequencedClientError: Error, Sendable {
    case unexpectedResponseType
}

private struct SensitiveTestError: LocalizedError, Sendable {
    static let secret = "secret-token-and-user@example.com"
    var errorDescription: String? { Self.secret }
}

private func entitlementResponse(
    plan: Entitlement.Plan,
    status: String? = nil,
    source: String? = nil
) -> EntitlementResponse {
    EntitlementResponse(
        entitlement: Entitlement(
            plan: plan,
            proStatus: status,
            proSource: source,
            freeBookSlots: plan == .pro ? 0 : 2,
            unlockedBookIds: [],
            unlockedBooksCount: 0,
            remainingFreeStarts: plan == .pro ? 0 : 1,
            currentPeriodEnd: nil,
            cancelAtPeriodEnd: nil,
            licenseKey: nil,
            licenseExpiresAt: nil
        ),
        paywall: nil
    )
}
