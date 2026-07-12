import Testing
import Foundation
import Networking
@testable import PaywallFeature
import Models

// MARK: - Helpers

private func entitlement(
    plan: Entitlement.Plan,
    proStatus: String? = nil,
    proSource: String? = nil,
    currentPeriodEnd: String? = nil,
    cancelAtPeriodEnd: Bool? = nil,
    licenseKey: String? = nil,
    licenseExpiresAt: String? = nil
) -> Entitlement {
    Entitlement(
        plan: plan,
        proStatus: proStatus,
        proSource: proSource,
        freeBookSlots: 0,
        unlockedBookIds: [],
        unlockedBooksCount: 0,
        remainingFreeStarts: 0,
        currentPeriodEnd: currentPeriodEnd,
        cancelAtPeriodEnd: cancelAtPeriodEnd,
        licenseKey: licenseKey,
        licenseExpiresAt: licenseExpiresAt
    )
}

private let futureDateStr = "2099-12-31T00:00:00Z"
private let pastDateStr = "2020-01-01T00:00:00Z"

// MARK: - State Computation Tests

@Suite("SubscriptionManagementModel — state computation")
struct SubscriptionManagementStateTests {

    // MARK: Free

    @Test("Free user → .free state")
    func freeUser() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .free),
            skStatus: .notSubscribed
        )
        #expect(state == .free)
        #expect(!state.isPro)
        #expect(!state.requiresBillingAttention)
    }

    @Test("Unknown plan → .free state (tolerant decoding)")
    func unknownPlanTreatedAsFree() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .unknown("ENTERPRISE")),
            skStatus: .notSubscribed
        )
        #expect(state == .free)
    }

    // MARK: Apple — Active

    @Test("Apple active → .appleActive with renewal date")
    func appleActive() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple",
                                     currentPeriodEnd: futureDateStr),
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil)
        )
        guard case .appleActive(let pid, let renewsAt) = state else {
            Issue.record("Expected .appleActive, got \(state)")
            return
        }
        #expect(pid == "com.cf.annual")
        #expect(renewsAt != nil)
        #expect(state.isPro)
        #expect(!state.requiresBillingAttention)
    }

    @Test("Apple active — SK unknown, backend confirms Pro → .appleActive")
    func appleActiveSkUnknown() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple",
                                     currentPeriodEnd: futureDateStr),
            skStatus: .unknown
        )
        guard case .appleActive = state else {
            Issue.record("Expected .appleActive, got \(state)")
            return
        }
        #expect(state.isPro)
    }

    // MARK: Apple — Cancelling

    @Test("Apple cancelling → .applyCancelling")
    func appleCancelling() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple",
                                     currentPeriodEnd: futureDateStr, cancelAtPeriodEnd: true),
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil)
        )
        guard case .applyCancelling = state else {
            Issue.record("Expected .applyCancelling, got \(state)")
            return
        }
        #expect(state.isPro)
        #expect(!state.requiresBillingAttention)
    }

    // MARK: Apple — Grace Period

    @Test("Grace period → .appleGracePeriod with attention")
    func appleGracePeriod() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple"),
            skStatus: .inGracePeriod(productID: "com.cf.annual", expirationDate: nil)
        )
        guard case .appleGracePeriod(let pid, _) = state else {
            Issue.record("Expected .appleGracePeriod, got \(state)")
            return
        }
        #expect(pid == "com.cf.annual")
        #expect(state.isPro)
        #expect(state.requiresBillingAttention)
    }

    // MARK: Apple — Billing Retry

    @Test("Billing retry → .appleBillingRetry with attention")
    func appleBillingRetry() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple"),
            skStatus: .inBillingRetry(productID: "com.cf.annual")
        )
        guard case .appleBillingRetry(let pid) = state else {
            Issue.record("Expected .appleBillingRetry, got \(state)")
            return
        }
        #expect(pid == "com.cf.annual")
        #expect(state.isPro)
        #expect(state.requiresBillingAttention)
    }

    // MARK: Apple — Expired

    @Test("Expired → .appleExpired, not Pro")
    func appleExpired() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "expired", proSource: "apple"),
            skStatus: .expired(productID: "com.cf.annual")
        )
        guard case .appleExpired(let pid) = state else {
            Issue.record("Expected .appleExpired, got \(state)")
            return
        }
        #expect(pid == "com.cf.annual")
        #expect(!state.isPro)
        #expect(!state.requiresBillingAttention)
    }

    // MARK: Apple — Revoked

    @Test("Revoked → .appleRevoked, not Pro")
    func appleRevoked() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple"),
            skStatus: .revoked
        )
        #expect(state == .appleRevoked)
        #expect(!state.isPro)
    }

    // MARK: Apple — Pending

    @Test("Pending → .applePending, Pro")
    func applePending() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "apple"),
            skStatus: .pending
        )
        #expect(state == .applePending)
        #expect(state.isPro)
    }

    // MARK: Stripe — Active

    @Test("Stripe active, auto-renew → .stripeActive(cancelsAtPeriodEnd: false)")
    func stripeActive() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "stripe",
                                     currentPeriodEnd: futureDateStr),
            skStatus: .notSubscribed
        )
        guard case .stripeActive(let renewsAt, let cancels) = state else {
            Issue.record("Expected .stripeActive, got \(state)")
            return
        }
        #expect(renewsAt != nil)
        #expect(!cancels)
        #expect(state.isPro)
        #expect(!state.requiresBillingAttention)
    }

    @Test("Stripe cancelling → .stripeActive(cancelsAtPeriodEnd: true)")
    func stripeCancelling() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "stripe",
                                     currentPeriodEnd: futureDateStr, cancelAtPeriodEnd: true),
            skStatus: .notSubscribed
        )
        guard case .stripeActive(_, let cancels) = state else {
            Issue.record("Expected .stripeActive, got \(state)")
            return
        }
        #expect(cancels)
    }

    @Test("Stripe past-due → .stripePastDue with attention")
    func stripePastDue() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "past_due", proSource: "stripe",
                                     currentPeriodEnd: futureDateStr),
            skStatus: .notSubscribed
        )
        guard case .stripePastDue = state else {
            Issue.record("Expected .stripePastDue, got \(state)")
            return
        }
        #expect(state.isPro)
        #expect(state.requiresBillingAttention)
    }

    // MARK: License

    @Test("License → .licenseActive with key and expiry")
    func licenseActive() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "license",
                                     licenseKey: "CF-TEST-KEY", licenseExpiresAt: futureDateStr),
            skStatus: .notSubscribed
        )
        guard case .licenseActive(let key, let expiresAt) = state else {
            Issue.record("Expected .licenseActive, got \(state)")
            return
        }
        #expect(key == "CF-TEST-KEY")
        #expect(expiresAt != nil)
        #expect(state.isPro)
    }

    @Test("License without expiry → .licenseActive with nil expiresAt")
    func licenseNoExpiry() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "license"),
            skStatus: .notSubscribed
        )
        guard case .licenseActive(_, let expiresAt) = state else {
            Issue.record("Expected .licenseActive, got \(state)")
            return
        }
        #expect(expiresAt == nil)
    }

    // MARK: Gift

    @Test("Gift code → .giftActive with expiry")
    func giftActive() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "gift_code",
                                     currentPeriodEnd: futureDateStr),
            skStatus: .notSubscribed
        )
        guard case .giftActive(let expiresAt) = state else {
            Issue.record("Expected .giftActive, got \(state)")
            return
        }
        #expect(expiresAt != nil)
        #expect(state.isPro)
    }

    // MARK: Admin / Other

    @Test("Admin grant → .adminOrOther")
    func adminGrant() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "admin"),
            skStatus: .notSubscribed
        )
        guard case .adminOrOther(let sourceName, _) = state else {
            Issue.record("Expected .adminOrOther, got \(state)")
            return
        }
        #expect(!sourceName.isEmpty)
    }

    @Test("Unknown source → .adminOrOther")
    func unknownSource() {
        let state = SubscriptionManagementModel.computeState(
            entitlement: entitlement(plan: .pro, proStatus: "active", proSource: "partner_deal"),
            skStatus: .notSubscribed
        )
        guard case .adminOrOther(let sourceName, _) = state else {
            Issue.record("Expected .adminOrOther, got \(state)")
            return
        }
        #expect(sourceName == "partner_deal")
    }

    // MARK: Source kind

    @Test("Source kind matches state for every case")
    func sourceKindMapping() {
        let cases: [(SubscriptionDetailState, ProSourceKind)] = [
            (.appleActive(productID: "", renewsAt: nil), .apple),
            (.applyCancelling(productID: "", expiresAt: nil), .apple),
            (.appleGracePeriod(productID: "", expiresAt: nil), .apple),
            (.appleBillingRetry(productID: ""), .apple),
            (.appleExpired(productID: ""), .apple),
            (.appleRevoked, .apple),
            (.applePending, .apple),
            (.stripeActive(renewsAt: nil, cancelsAtPeriodEnd: false), .stripe),
            (.stripePastDue(renewsAt: nil), .stripe),
            (.licenseActive(key: nil, expiresAt: nil), .license),
            (.giftActive(expiresAt: nil), .gift),
            (.adminOrOther(sourceName: "admin", expiresAt: nil), .admin),
        ]
        for (state, expected) in cases {
            #expect(state.proSourceKind == expected, "State \(state) should have source \(expected)")
        }
        #expect(ProSourceKind(rawSource: nil) == .unknown)
        #expect(!ProSourceKind(rawSource: nil).isApple)
    }

    @Test("offer-code redemption requires an existing Apple-backed mapping")
    func offerCodeRequiresMappedAppleState() {
        let permitted: [SubscriptionDetailState] = [
            .appleActive(productID: "monthly", renewsAt: nil),
            .applyCancelling(productID: "annual", expiresAt: nil),
            .appleGracePeriod(productID: "monthly", expiresAt: nil),
            .appleBillingRetry(productID: "monthly"),
            .appleExpired(productID: "annual"),
            .appleRevoked,
        ]
        let rejected: [SubscriptionDetailState] = [
            .applePending,
            .stripeActive(renewsAt: nil, cancelsAtPeriodEnd: false),
            .stripePastDue(renewsAt: nil),
            .licenseActive(key: nil, expiresAt: nil),
            .giftActive(expiresAt: nil),
            .adminOrOther(sourceName: "admin", expiresAt: nil),
            .free,
        ]

        for state in permitted {
            #expect(state.permitsOfferCodeRedemption)
        }
        for state in rejected {
            #expect(!state.permitsOfferCodeRedemption)
        }
    }

    @Test("free account cannot present tokenless offer-code redemption")
    @MainActor
    func freeAccountCannotRedeemOfferCode() {
        let model = SubscriptionManagementModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        model.inject(detailState: .free)

        model.redeemOfferCode()

        #expect(!model.showOfferCodeRedemption)
        #expect(model.errorMessage != nil)
    }

    @Test("mapped Apple account may present offer-code redemption")
    @MainActor
    func mappedAppleAccountCanRedeemOfferCode() {
        let model = SubscriptionManagementModel(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient()
        )
        model.inject(
            detailState: .appleActive(productID: "monthly", renewsAt: nil)
        )

        model.redeemOfferCode()

        #expect(model.showOfferCodeRedemption)
        #expect(model.errorMessage == nil)
    }

    // MARK: Date parsing

    @Test("Date parsing handles ISO-8601 with fractional seconds")
    func dateParsingWithFractions() {
        let date = SubscriptionManagementModel.parseDate("2024-06-01T10:30:00.000Z")
        #expect(date != nil)
    }

    @Test("Date parsing handles ISO-8601 without fractional seconds")
    func dateParsingWithoutFractions() {
        let date = SubscriptionManagementModel.parseDate("2024-06-01T10:30:00Z")
        #expect(date != nil)
    }

    @Test("Date parsing returns nil for nil input")
    func dateParsingNil() {
        #expect(SubscriptionManagementModel.parseDate(nil) == nil)
    }
}
