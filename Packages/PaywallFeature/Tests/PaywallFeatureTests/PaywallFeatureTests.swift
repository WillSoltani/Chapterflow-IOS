import Testing
import Foundation
import StoreKit
import Models
import CoreKit
import Networking
@testable import PaywallFeature

// StoreKit 18.4+ adds `SubscriptionStatus` as a typealias — disambiguate.
private typealias SubscriptionStatus = PaywallFeature.SubscriptionStatus

// MARK: - Module smoke test

@Suite("PaywallFeature")
struct PaywallFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(PaywallFeatureModule.moduleName == "PaywallFeature")
    }
}

// MARK: - EntitlementReconciler tests

@Suite("EntitlementReconciler — source preference + never-double-charge")
struct EntitlementReconcilerTests {

    private let reconciler = EntitlementReconciler()

    // MARK: - Fixtures

    private func freeEntitlement(currentPeriodEnd: String? = nil) -> Entitlement {
        Entitlement(
            plan: .free, proStatus: nil, proSource: nil,
            freeBookSlots: 2, unlockedBookIds: [], unlockedBooksCount: 0,
            remainingFreeStarts: 1, currentPeriodEnd: currentPeriodEnd,
            cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
        )
    }

    private func proEntitlement(source: String, periodEnd: String? = nil) -> Entitlement {
        Entitlement(
            plan: .pro, proStatus: "active", proSource: source,
            freeBookSlots: 0, unlockedBookIds: [], unlockedBooksCount: 0,
            remainingFreeStarts: 0, currentPeriodEnd: periodEnd,
            cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
        )
    }

    private let appleProductIds: Set<String> = [
        "com.chapterflow.ios.pro.monthly",
        "com.chapterflow.ios.pro.annual"
    ]

    // MARK: - Free user, no StoreKit

    @Test("free user with no StoreKit subscription → useBackend")
    func freeNoStoreKit() {
        let action = reconciler.reconcile(
            backend: freeEntitlement(),
            storeKitActiveProductIds: [],
            storeKitLatestExpiryDate: nil,
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - Stripe Pro user (web subscription)

    @Test("Stripe-Pro backend + no StoreKit subscription → useBackend (already Pro via web)")
    func stripeProNoStoreKit() {
        let action = reconciler.reconcile(
            backend: proEntitlement(source: "stripe"),
            storeKitActiveProductIds: [],
            storeKitLatestExpiryDate: nil,
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    @Test("Stripe-Pro backend + non-matching StoreKit product → useBackend")
    func stripeProWithUnknownStoreKitProduct() {
        let action = reconciler.reconcile(
            backend: proEntitlement(source: "stripe"),
            storeKitActiveProductIds: ["com.other.app.subscription"],
            storeKitLatestExpiryDate: nil,
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - Apple Pro, backend in sync

    @Test("Apple-Pro backend with matching StoreKit expiry → useBackend (in sync)")
    func appleProInSync() {
        let periodEnd = Date(timeIntervalSinceNow: 86400 * 30)   // 30 days
        let storeKitExpiry = periodEnd                            // same — in sync

        let action = reconciler.reconcile(
            backend: proEntitlement(source: "apple", periodEnd: iso8601(periodEnd)),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.annual"],
            storeKitLatestExpiryDate: storeKitExpiry,
            backendPeriodEndDate: periodEnd,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    @Test("Apple-Pro backend with earlier StoreKit expiry → useBackend (backend is ahead)")
    func appleProBackendAhead() {
        let backendEnd = Date(timeIntervalSinceNow: 86400 * 60)  // 60 days (backend)
        let storeKitExpiry = Date(timeIntervalSinceNow: 86400 * 30)  // 30 days (SK older)

        let action = reconciler.reconcile(
            backend: proEntitlement(source: "apple", periodEnd: iso8601(backendEnd)),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.annual"],
            storeKitLatestExpiryDate: storeKitExpiry,
            backendPeriodEndDate: backendEnd,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - Renewal detected: StoreKit newer than backend

    @Test("Apple-Pro backend + StoreKit has later expiry → triggerAppleVerify (renewal)")
    func appleProRenewalDetected() {
        let backendEnd = Date(timeIntervalSinceNow: 86400 * 5)   // 5 days (old period)
        let storeKitExpiry = Date(timeIntervalSinceNow: 86400 * 35)  // 35 days (renewal)

        let action = reconciler.reconcile(
            backend: proEntitlement(source: "apple", periodEnd: iso8601(backendEnd)),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.annual"],
            storeKitLatestExpiryDate: storeKitExpiry,
            backendPeriodEndDate: backendEnd,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .triggerAppleVerify(productIds: ["com.chapterflow.ios.pro.annual"]))
    }

    // MARK: - Free backend + active Apple subscription (purchase not yet processed)

    @Test("Free backend + active Apple subscription → triggerAppleVerify")
    func freeBackendAppleSubActive() {
        let action = reconciler.reconcile(
            backend: freeEntitlement(),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.monthly"],
            storeKitLatestExpiryDate: Date(timeIntervalSinceNow: 86400 * 30),
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .triggerAppleVerify(productIds: ["com.chapterflow.ios.pro.monthly"]))
    }

    @Test("Free backend + annual Apple subscription → triggerAppleVerify with correct product")
    func freeBackendAnnualAppleSub() {
        let action = reconciler.reconcile(
            backend: freeEntitlement(),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.annual"],
            storeKitLatestExpiryDate: Date(timeIntervalSinceNow: 86400 * 365),
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .triggerAppleVerify(productIds: ["com.chapterflow.ios.pro.annual"]))
    }

    @Test("Free backend + active non-Apple product → useBackend (not our product)")
    func freeBackendNonAppleProduct() {
        let action = reconciler.reconcile(
            backend: freeEntitlement(),
            storeKitActiveProductIds: ["com.competitor.app.premium"],
            storeKitLatestExpiryDate: Date(timeIntervalSinceNow: 86400 * 30),
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - Apple-Pro with no StoreKit expiry date (non-renewing)

    @Test("Apple-Pro backend + active StoreKit with nil expiry → useBackend (cannot compare)")
    func appleProNilExpiryCannotCompare() {
        let backendEnd = Date(timeIntervalSinceNow: 86400 * 30)

        let action = reconciler.reconcile(
            backend: proEntitlement(source: "apple", periodEnd: iso8601(backendEnd)),
            storeKitActiveProductIds: ["com.chapterflow.ios.pro.annual"],
            storeKitLatestExpiryDate: nil,  // nil expiry → can't compare
            backendPeriodEndDate: backendEnd,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - License / gift / admin sources

    @Test("License-Pro backend + no StoreKit → useBackend (license doesn't use Apple)")
    func licensePro() {
        let action = reconciler.reconcile(
            backend: proEntitlement(source: "license"),
            storeKitActiveProductIds: [],
            storeKitLatestExpiryDate: nil,
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    @Test("Admin-Pro backend + no StoreKit → useBackend")
    func adminPro() {
        let action = reconciler.reconcile(
            backend: proEntitlement(source: "admin"),
            storeKitActiveProductIds: [],
            storeKitLatestExpiryDate: nil,
            backendPeriodEndDate: nil,
            knownAppleProductIds: appleProductIds
        )
        #expect(action == .useBackend)
    }

    // MARK: - SubscriptionStatus extension helpers

    @Test("SubscriptionStatus.subscribed → activeProductIds contains product")
    func subscriptionStatusActiveIds() {
        let status = SubscriptionStatus.subscribed(productID: "com.cf.annual", expirationDate: nil)
        #expect(status.activeProductIds == ["com.cf.annual"])
    }

    @Test("SubscriptionStatus.inGracePeriod → still counted as active")
    func gracePeriodStillActive() {
        let exp = Date(timeIntervalSinceNow: 86400)
        let status = SubscriptionStatus.inGracePeriod(productID: "com.cf.annual", expirationDate: exp)
        #expect(status.activeProductIds == ["com.cf.annual"])
        #expect(status.latestExpiryDate == exp)
    }

    @Test("SubscriptionStatus.notSubscribed → empty activeProductIds")
    func notSubscribedEmpty() {
        let status = SubscriptionStatus.notSubscribed
        #expect(status.activeProductIds.isEmpty)
        #expect(status.latestExpiryDate == nil)
    }

    @Test("SubscriptionStatus.revoked → empty activeProductIds")
    func revokedEmpty() {
        #expect(SubscriptionStatus.revoked.activeProductIds.isEmpty)
    }

    @Test("SubscriptionStatus.expired → empty activeProductIds")
    func expiredEmpty() {
        #expect(SubscriptionStatus.expired(productID: "com.cf.annual").activeProductIds.isEmpty)
    }

    // MARK: - Helpers

    private func iso8601(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: date)
    }
}

// MARK: - Paywall guard: never sell to already-Pro user

@Suite("PaywallModel — already-Pro guard")
struct PaywallModelAlreadyProGuardTests {

    private let appleProductIds: Set<String> = [
        "com.chapterflow.ios.pro.monthly",
        "com.chapterflow.ios.pro.annual"
    ]

    @Test("Stripe-Pro user: subscriptionStatus.isPro is true → paywall does NOT sell")
    func stripePro_paywallIsPro() async throws {
        let mock = MockAPIClient()
        let entitlementResponse = EntitlementResponse(
            entitlement: Entitlement(
                plan: .pro, proStatus: "active", proSource: "stripe",
                freeBookSlots: 0, unlockedBookIds: [], unlockedBooksCount: 0,
                remainingFreeStarts: 0, currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
            ),
            paywall: nil
        )
        try await mock.setStub(entitlementResponse, for: "/book/me/entitlements")

        let model = await PaywallModel(
            storeKitService: MockStoreKitService(),
            apiClient: mock
        )
        await model.refreshEntitlement()
        let status = await model.subscriptionStatus
        let source = await model.proSource
        #expect(status.isPro == true)
        #expect(source == "stripe")
    }

    @Test("Apple-Pro user: subscriptionStatus.isPro is true → paywall does NOT sell")
    func applePro_paywallIsPro() async throws {
        let mock = MockAPIClient()
        let entitlementResponse = EntitlementResponse(
            entitlement: Entitlement(
                plan: .pro, proStatus: "active", proSource: "apple",
                freeBookSlots: 0, unlockedBookIds: [], unlockedBooksCount: 0,
                remainingFreeStarts: 0, currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
            ),
            paywall: nil
        )
        try await mock.setStub(entitlementResponse, for: "/book/me/entitlements")

        let model = await PaywallModel(
            storeKitService: MockStoreKitService(),
            apiClient: mock
        )
        await model.refreshEntitlement()
        let status = await model.subscriptionStatus
        #expect(status.isPro == true)
        let source = await model.proSource
        #expect(source == "apple")
    }

    @Test("License-Pro user: subscriptionStatus.isPro is true → paywall does NOT sell")
    func licensePro_paywallIsPro() async throws {
        let mock = MockAPIClient()
        let entitlementResponse = EntitlementResponse(
            entitlement: Entitlement(
                plan: .pro, proStatus: "active", proSource: "license",
                freeBookSlots: 0, unlockedBookIds: [], unlockedBooksCount: 0,
                remainingFreeStarts: 0, currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
            ),
            paywall: nil
        )
        try await mock.setStub(entitlementResponse, for: "/book/me/entitlements")

        let model = await PaywallModel(
            storeKitService: MockStoreKitService(),
            apiClient: mock
        )
        await model.refreshEntitlement()
        let status = await model.subscriptionStatus
        #expect(status.isPro == true)
        let source = await model.proSource
        #expect(source == "license")
    }

    @Test("Free user: subscriptionStatus.isPro is false → paywall CAN sell")
    func freeUser_paywallCanSell() async throws {
        let mock = MockAPIClient()
        let entitlementResponse = EntitlementResponse(
            entitlement: Entitlement(
                plan: .free, proStatus: nil, proSource: nil,
                freeBookSlots: 2, unlockedBookIds: [], unlockedBooksCount: 0,
                remainingFreeStarts: 1, currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil, licenseKey: nil, licenseExpiresAt: nil
            ),
            paywall: nil
        )
        try await mock.setStub(entitlementResponse, for: "/book/me/entitlements")

        let model = await PaywallModel(
            storeKitService: MockStoreKitService(),
            apiClient: mock
        )
        await model.refreshEntitlement()
        let status = await model.subscriptionStatus
        #expect(status.isPro == false)
        let source = await model.proSource
        #expect(source == nil)
    }
}

// MARK: - Mock StoreKit service (test double)

private actor MockStoreKitService: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void> = AsyncStream { _ in }
    var mockStatus: SubscriptionStatus = .notSubscribed

    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus { mockStatus }
    func currentTransactionID() async -> UInt64? { nil }
}
