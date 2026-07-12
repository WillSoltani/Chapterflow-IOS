import SwiftUI
import StoreKit
import Models
import Networking
import Persistence

// MARK: - Preview helpers

private actor PreviewSKService: StoreKitServicing {
    private let status: SubscriptionStatus
    private let transactionID: UInt64?

    init(status: SubscriptionStatus = .notSubscribed, transactionID: UInt64? = nil) {
        self.status = status
        self.transactionID = transactionID
    }

    func entitlementChanges() async -> AsyncStream<Void> { AsyncStream { _ in } }
    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus { status }
    func currentTransactionID() async -> UInt64? { transactionID }
}

@MainActor
private func previewModel(
    plan: Entitlement.Plan,
    proStatus: String? = nil,
    proSource: String? = nil,
    currentPeriodEnd: String? = nil,
    cancelAtPeriodEnd: Bool? = nil,
    licenseKey: String? = nil,
    licenseExpiresAt: String? = nil,
    skStatus: SubscriptionStatus = .notSubscribed,
    transactionID: UInt64? = nil
) -> SubscriptionManagementModel {
    let entitlement = Entitlement(
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
    let state = SubscriptionManagementModel.computeState(entitlement: entitlement, skStatus: skStatus)
    let model = SubscriptionManagementModel(
        storeKitService: PreviewSKService(status: skStatus, transactionID: transactionID),
        apiClient: MockAPIClient()
    )
    model.inject(detailState: state, transactionID: transactionID)
    return model
}

private let futureDate = "2025-12-31T00:00:00Z"
private let pastDate = "2024-01-01T00:00:00Z"

// MARK: - Previews

#Preview("Apple — Active") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            currentPeriodEnd: futureDate,
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil),
            transactionID: 12_345
        )
    )
}

#Preview("Apple — Active (Dark)") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            currentPeriodEnd: futureDate,
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil),
            transactionID: 12_345
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Apple — Active (XXL)") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            currentPeriodEnd: futureDate,
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil),
            transactionID: 12_345
        )
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Apple — Cancelling") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            currentPeriodEnd: futureDate,
            cancelAtPeriodEnd: true,
            skStatus: .subscribed(productID: "com.cf.annual", expirationDate: nil),
            transactionID: 12_345
        )
    )
}

#Preview("Apple — Grace Period") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            currentPeriodEnd: futureDate,
            skStatus: .inGracePeriod(productID: "com.cf.annual", expirationDate: nil)
        )
    )
}

#Preview("Apple — Billing Retry") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            skStatus: .inBillingRetry(productID: "com.cf.annual")
        )
    )
}

#Preview("Apple — Expired") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "expired",
            proSource: "apple",
            skStatus: .expired(productID: "com.cf.annual")
        )
    )
}

#Preview("Apple — Revoked") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            skStatus: .revoked
        )
    )
}

#Preview("Stripe — Active") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "stripe",
            currentPeriodEnd: futureDate
        )
    )
}

#Preview("Stripe — Cancelling") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "stripe",
            currentPeriodEnd: futureDate,
            cancelAtPeriodEnd: true
        )
    )
}

#Preview("Stripe — Past Due") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "past_due",
            proSource: "stripe",
            currentPeriodEnd: futureDate
        )
    )
}

#Preview("License — Active") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "license",
            licenseKey: "CF-XXXX-YYYY-ZZZZ",
            licenseExpiresAt: futureDate
        )
    )
}

#Preview("Gift — Active") {
    SubscriptionManagementView(
        model: previewModel(
            plan: .pro,
            proStatus: "active",
            proSource: "gift_code",
            currentPeriodEnd: futureDate
        )
    )
}

#Preview("Free") {
    SubscriptionManagementView(
        model: previewModel(plan: .free)
    )
}
