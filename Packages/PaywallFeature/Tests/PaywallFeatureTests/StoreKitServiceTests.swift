import Testing
import Foundation
import StoreKit
import CoreKit
import Networking
import Models
@testable import PaywallFeature

// StoreKit 18.4 added `SubscriptionStatus` as a typealias — disambiguate explicitly.
private typealias SubscriptionStatus = PaywallFeature.SubscriptionStatus

// MARK: - SubscriptionStatus tests

@Suite("SubscriptionStatus")
struct SubscriptionStatusTests {

    @Test("isPro is true for .subscribed")
    func isProSubscribed() {
        let status = SubscriptionStatus.subscribed(productID: "x", expirationDate: nil)
        #expect(status.isPro)
    }

    @Test("isPro is true for .inGracePeriod")
    func isProGracePeriod() {
        let status = SubscriptionStatus.inGracePeriod(productID: "x", expirationDate: nil)
        #expect(status.isPro)
    }

    @Test("isPro is false for .notSubscribed")
    func isProNotSubscribed() {
        #expect(!SubscriptionStatus.notSubscribed.isPro)
    }

    @Test("isPro is false for .expired")
    func isProExpired() {
        #expect(!SubscriptionStatus.expired(productID: "x").isPro)
    }

    @Test("isPro is false for .revoked")
    func isProRevoked() {
        #expect(!SubscriptionStatus.revoked.isPro)
    }

    @Test("isPro is false for .unknown")
    func isProUnknown() {
        #expect(!SubscriptionStatus.unknown.isPro)
    }

    @Test("isPro is false for .pending")
    func isProPending() {
        #expect(!SubscriptionStatus.pending.isPro)
    }

    @Test("isPro is false for .inBillingRetry")
    func isProBillingRetry() {
        #expect(!SubscriptionStatus.inBillingRetry(productID: "x").isPro)
    }

    @Test("requiresAttention for .inGracePeriod")
    func requiresAttentionGracePeriod() {
        let status = SubscriptionStatus.inGracePeriod(productID: "x", expirationDate: nil)
        #expect(status.requiresAttention)
    }

    @Test("requiresAttention for .inBillingRetry")
    func requiresAttentionBillingRetry() {
        #expect(SubscriptionStatus.inBillingRetry(productID: "x").requiresAttention)
    }

    @Test("requiresAttention is false for .subscribed")
    func requiresAttentionFalseForSubscribed() {
        let status = SubscriptionStatus.subscribed(productID: "x", expirationDate: nil)
        #expect(!status.requiresAttention)
    }

    @Test("requiresAttention is false for .notSubscribed")
    func requiresAttentionFalseForNotSubscribed() {
        #expect(!SubscriptionStatus.notSubscribed.requiresAttention)
    }

    @Test("isLapsed is true for .expired")
    func isLapsedExpired() {
        #expect(SubscriptionStatus.expired(productID: "x").isLapsed)
    }

    @Test("isLapsed is true for .revoked")
    func isLapsedRevoked() {
        #expect(SubscriptionStatus.revoked.isLapsed)
    }

    @Test("isLapsed is false for .subscribed")
    func isLapsedSubscribed() {
        #expect(!SubscriptionStatus.subscribed(productID: "x", expirationDate: nil).isLapsed)
    }

    @Test("isLapsed is false for .notSubscribed")
    func isLapsedNotSubscribed() {
        #expect(!SubscriptionStatus.notSubscribed.isLapsed)
    }

    @Test("isLapsed is false for .inGracePeriod")
    func isLapsedGracePeriod() {
        #expect(!SubscriptionStatus.inGracePeriod(productID: "x", expirationDate: nil).isLapsed)
    }

    @Test("displayLabel returns correct strings")
    func displayLabels() {
        #expect(SubscriptionStatus.unknown.displayLabel == "Loading")
        #expect(SubscriptionStatus.notSubscribed.displayLabel == "Free")
        #expect(SubscriptionStatus.subscribed(productID: "x", expirationDate: nil).displayLabel == "Pro")
        #expect(SubscriptionStatus.pending.displayLabel == "Pending")
        #expect(SubscriptionStatus.inGracePeriod(productID: "x", expirationDate: nil).displayLabel == "Grace Period")
        #expect(SubscriptionStatus.inBillingRetry(productID: "x").displayLabel == "Payment Issue")
        #expect(SubscriptionStatus.revoked.displayLabel == "Revoked")
        #expect(SubscriptionStatus.expired(productID: "x").displayLabel == "Expired")
    }

    @Test("subscribed Equatable with same values")
    func equalitySubscribed() {
        let a = SubscriptionStatus.subscribed(productID: "com.cf.annual", expirationDate: nil)
        let b = SubscriptionStatus.subscribed(productID: "com.cf.annual", expirationDate: nil)
        #expect(a == b)
    }

    @Test("subscribed Equatable with different productIDs")
    func inequalitySubscribed() {
        let a = SubscriptionStatus.subscribed(productID: "com.cf.annual", expirationDate: nil)
        let b = SubscriptionStatus.subscribed(productID: "com.cf.monthly", expirationDate: nil)
        #expect(a != b)
    }
}

// MARK: - StoreProductInfo tests

@Suite("StoreProductInfo")
struct StoreProductInfoTests {

    @Test("init stores all fields correctly")
    func initFields() {
        let info = StoreProductInfo(
            id: "com.cf.annual",
            displayName: "Annual",
            displayPrice: "$49.99",
            periodLabel: "year",
            isPopular: true,
            introductoryOfferText: "7-day free trial"
        )
        #expect(info.id == "com.cf.annual")
        #expect(info.displayName == "Annual")
        #expect(info.displayPrice == "$49.99")
        #expect(info.periodLabel == "year")
        #expect(info.isPopular)
        #expect(info.introductoryOfferText == "7-day free trial")
    }

    @Test("Equatable for identical instances")
    func equatable() {
        let a = StoreProductInfo(
            id: "x", displayName: "X", displayPrice: "$1", periodLabel: "month", isPopular: false
        )
        let b = StoreProductInfo(
            id: "x", displayName: "X", displayPrice: "$1", periodLabel: "month", isPopular: false
        )
        #expect(a == b)
    }

    @Test("Equatable returns false for different IDs")
    func inequatable() {
        let a = StoreProductInfo(
            id: "a", displayName: "A", displayPrice: "$1", periodLabel: "month", isPopular: false
        )
        let b = StoreProductInfo(
            id: "b", displayName: "B", displayPrice: "$2", periodLabel: "year", isPopular: true
        )
        #expect(a != b)
    }
}

// MARK: - PurchaseState tests

@Suite("PurchaseState")
struct PurchaseStateTests {

    @Test("isInProgress is true for .purchasing")
    func isInProgressPurchasing() {
        #expect(PurchaseState.purchasing.isInProgress)
    }

    @Test("isInProgress is true for .restoring")
    func isInProgressRestoring() {
        #expect(PurchaseState.restoring.isInProgress)
    }

    @Test("isInProgress is false for .idle")
    func isInProgressIdle() {
        #expect(!PurchaseState.idle.isInProgress)
    }

    @Test("isInProgress is true for .pendingApproval")
    func isInProgressPending() {
        #expect(PurchaseState.pendingApproval.isInProgress)
    }

    @Test("isInProgress is true while backend access is being confirmed")
    func isInProgressConfirmingAccess() {
        #expect(PurchaseState.confirmingAccess.isInProgress)
    }

    @Test("isInProgress is false for .failed")
    func isInProgressFailed() {
        #expect(!PurchaseState.failed("error").isInProgress)
    }

    @Test("Equatable for .idle")
    func equatableIdle() {
        #expect(PurchaseState.idle == .idle)
    }

    @Test("Equatable for .failed with same message")
    func equatableFailed() {
        #expect(PurchaseState.failed("oops") == .failed("oops"))
    }

    @Test("Equatable for .failed with different messages")
    func inequatableFailed() {
        #expect(PurchaseState.failed("a") != .failed("b"))
    }
}

// MARK: - BillingEndpoints tests

@Suite("BillingEndpoints")
struct BillingEndpointsTests {

    @Test("verifyApplePurchase endpoint has correct path and method")
    func endpointShape() throws {
        let endpoint = try Endpoints.verifyApplePurchase(jwsRepresentation: "test.jws.payload")
        #expect(endpoint.path == "/book/me/billing/apple/verify")
        #expect(endpoint.method == .post)
        #expect(endpoint.requiresAuth)
        #expect(endpoint.httpBody != nil)
    }

    @Test("verifyApplePurchase body encodes transactionJWS field")
    func endpointBodyContainsJWS() throws {
        let jws = "header.payload.signature"
        let endpoint = try Endpoints.verifyApplePurchase(jwsRepresentation: jws)
        guard let body = endpoint.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: String]
        else {
            Issue.record("Body is nil or not a JSON object")
            return
        }
        #expect(json["transactionJWS"] == jws)
    }
}

// MARK: - PaywallModel tests

@Suite("PaywallModel")
@MainActor
struct PaywallModelTests {

    @Test("initial state is correct")
    func initialState() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.productInfos.isEmpty)
        #expect(model.subscriptionStatus == .unknown)
        #expect(model.purchaseState == .idle)
        #expect(!model.isLoadingProducts)
        #expect(model.productAvailability == .idle)
        #expect(model.errorMessage == nil)
    }

    @Test("inject sets productInfos and status")
    func injectState() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        let products = [
            StoreProductInfo(id: "x", displayName: "X", displayPrice: "$1",
                             periodLabel: "month", isPopular: false)
        ]
        model.inject(
            productInfos: products,
            status: .subscribed(productID: "x", expirationDate: nil),
            entitlementResolution: .resolvedPro
        )
        #expect(model.productInfos.count == 1)
        #expect(model.subscriptionStatus == .subscribed(productID: "x", expirationDate: nil))
    }

    @Test("initialProductInfos and initialStatus init sets state")
    func initWithState() {
        let products = [
            StoreProductInfo(id: "y", displayName: "Y", displayPrice: "$5",
                             periodLabel: "year", isPopular: true)
        ]
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            initialProductInfos: products,
            initialStatus: .notSubscribed
        )
        #expect(model.productInfos.count == 1)
        #expect(model.subscriptionStatus == .notSubscribed)
        #expect(model.entitlementResolution == .unresolved)
    }

    @Test("loadProducts exposes a StoreKit failure without leaking an error")
    func loadProductsError() async {
        let service = StubStoreKitService(throwOnLoad: true)
        let model = PaywallModel(
            storeKitService: service,
            apiClient: MockAPIClient()
        )
        await model.loadProducts()
        #expect(model.productAvailability == .storeUnavailable)
        #expect(model.errorMessage == nil)
        #expect(model.productInfos.isEmpty)
    }

    @Test("loadProducts clears products on empty result")
    func loadProductsEmpty() async {
        let service = StubStoreKitService(throwOnLoad: false)
        let model = PaywallModel(
            storeKitService: service,
            apiClient: MockAPIClient()
        )
        await model.loadProducts()
        #expect(model.productInfos.isEmpty)
        #expect(model.productAvailability == .storeUnavailable)
        #expect(model.errorMessage == nil)
    }

    @Test("loadProducts distinguishes invalid build configuration")
    func loadProductsInvalidConfiguration() async {
        let service = StubStoreKitService(loadFailure: .invalidConfiguration)
        let model = PaywallModel(storeKitService: service, apiClient: MockAPIClient())
        await model.loadProducts()
        #expect(model.productAvailability == .configurationInvalid)
        #expect(!model.productAvailability.canRetry)
        #expect(model.errorMessage == nil)
    }

    @Test("loadProducts distinguishes an offline device")
    func loadProductsOffline() async {
        let service = StubStoreKitService(loadFailure: .offline)
        let model = PaywallModel(storeKitService: service, apiClient: MockAPIClient())
        await model.loadProducts()
        #expect(model.productAvailability == .networkUnavailable)
        #expect(model.productAvailability.canRetry)
        #expect(model.errorMessage == nil)
    }

    @Test("loadProducts cancellation is not presented as a failure")
    func loadProductsCancellation() async {
        let service = StubStoreKitService(loadFailure: .cancelled)
        let model = PaywallModel(storeKitService: service, apiClient: MockAPIClient())

        await model.loadProducts()

        #expect(model.productAvailability == .idle)
        #expect(model.errorMessage == nil)
    }

    @Test("repeated product loads are single-flight")
    func loadProductsSingleFlight() async {
        let service = SlowEmptyStoreKitService()
        let model = PaywallModel(storeKitService: service, apiClient: MockAPIClient())
        let started = Task {
            for await _ in service.loadStarted { return }
        }
        let firstLoad = Task { await model.loadProducts() }
        await started.value

        await model.loadProducts()
        await service.finishLoad()
        await firstLoad.value

        #expect(await service.loadCallCount() == 1)
        #expect(model.productAvailability == .storeUnavailable)
    }

    @Test("injected products make the paywall actionable")
    func injectedProductsAreAvailable() {
        let product = StoreProductInfo(
            id: "com.cf.monthly",
            displayName: "Monthly",
            displayPrice: "$5.99",
            periodLabel: "month",
            isPopular: false
        )
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            initialProductInfos: [product]
        )
        #expect(model.productAvailability == .available)
    }

    @Test("purchase with unknown productID sets errorMessage")
    func purchaseUnknownProduct() async {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        await model.purchase(productID: "nonexistent")
        #expect(model.errorMessage != nil)
    }

    @Test("restorePurchases sets error on service failure")
    func restoreFailure() async {
        let service = StubStoreKitService(throwOnRestore: true)
        let model = PaywallModel(
            storeKitService: service,
            apiClient: MockAPIClient()
        )
        await model.restorePurchases()
        #expect(model.purchaseState != .restoring)
        #expect(model.errorMessage != nil)
        #expect(model.errorMessage != "Restore failed")
    }

    @Test("context defaults to settings")
    func contextDefaults() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.context == .settings)
    }

    @Test("context is set from init")
    func contextFromInit() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            context: .bookDetail(bookTitle: "Thinking Fast and Slow")
        )
        #expect(model.context == .bookDetail(bookTitle: "Thinking Fast and Slow"))
    }

    @Test("selectProduct updates selectedProductID")
    func selectProduct() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        model.selectProduct("com.cf.annual")
        #expect(model.selectedProductID == "com.cf.annual")
    }

    @Test("selectProduct replaces previous selection")
    func selectProductReplaces() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        model.selectProduct("com.cf.annual")
        model.selectProduct("com.cf.monthly")
        #expect(model.selectedProductID == "com.cf.monthly")
    }

    @Test("annualSavingsPercent returns nil when products are empty")
    func savingsPercentNoProducts() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.annualSavingsPercent == nil)
    }

    @Test("annualSavingsPercent returns nil when priceDecimalValue is missing")
    func savingsPercentNoPriceValue() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            initialProductInfos: [
                StoreProductInfo(id: "a", displayName: "Annual", displayPrice: "$49.99",
                                 periodLabel: "year", isPopular: true),
                StoreProductInfo(id: "b", displayName: "Monthly", displayPrice: "$5.99",
                                 periodLabel: "month", isPopular: false)
            ]
        )
        #expect(model.annualSavingsPercent == nil)
    }

    @Test("annualSavingsPercent computes correct percentage")
    func savingsPercentComputed() {
        // Monthly: $5.99 × 12 = $71.88 vs Annual: $49.99 → save ~30%
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            initialProductInfos: [
                StoreProductInfo(id: "a", displayName: "Annual", displayPrice: "$49.99",
                                 periodLabel: "year", isPopular: true, priceDecimalValue: 49.99),
                StoreProductInfo(id: "b", displayName: "Monthly", displayPrice: "$5.99",
                                 periodLabel: "month", isPopular: false, priceDecimalValue: 5.99)
            ]
        )
        let pct = model.annualSavingsPercent
        #expect(pct != nil)
        // $71.88 - $49.99 = $21.89 / $71.88 ≈ 30%
        #expect((pct ?? 0) > 20)
        #expect((pct ?? 0) < 45)
    }

    @Test("PurchaseState success case has correct productID")
    func purchaseStateSuccessEquality() {
        let stateA = PurchaseState.success(productID: "com.cf.annual")
        let stateB = PurchaseState.success(productID: "com.cf.annual")
        let stateC = PurchaseState.success(productID: "com.cf.monthly")
        #expect(stateA == stateB)
        #expect(stateA != stateC)
    }

    @Test("PurchaseState success isInProgress is false")
    func purchaseStateSuccessNotInProgress() {
        #expect(!PurchaseState.success(productID: "x").isInProgress)
    }

    @Test("onAppear uses analytics noop by default")
    func onAppearNoopAnalytics() async {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            context: .bookDetail(bookTitle: "Test Book")
        )
        // Should not crash — NoopAnalyticsClient swallows events silently
        await model.onAppear()
    }

    @Test("onAppear with spy analytics records paywallViewed event")
    func onAppearTracksAnalytics() async {
        let spy = SpyAnalyticsClient()
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            analytics: spy,
            context: .lockedFeature(featureName: "Concept Graph")
        )
        await model.onAppear()
        let events = await spy.trackedEvents
        #expect(events.contains(.paywallViewed(source: "locked_feature")))
    }

    @Test("serverBenefits is nil initially")
    func serverBenefitsInitiallyNil() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        #expect(model.serverBenefits == nil)
    }

    @Test("inject sets serverBenefits")
    func injectServerBenefits() {
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        model.inject(
            productInfos: [],
            status: .notSubscribed,
            entitlementResolution: .resolvedFree,
            serverBenefits: ["Benefit A", "Benefit B"]
        )
        #expect(model.serverBenefits == ["Benefit A", "Benefit B"])
    }
}
