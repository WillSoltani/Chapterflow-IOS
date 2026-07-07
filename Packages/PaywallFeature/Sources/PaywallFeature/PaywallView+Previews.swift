import SwiftUI
import StoreKit
import Networking
import DesignSystem

// MARK: - Previews

#Preview("Default — not subscribed", traits: .sizeThatFitsLayout) {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: []))
        .frame(maxHeight: 700)
}

#Preview("With products — settings context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: previewSampleProducts,
        context: .settings
    ))
}

#Preview("Book detail context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: previewSampleProducts,
        context: .bookDetail(bookTitle: "Atomic Habits")
    ))
}

#Preview("Locked feature context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: previewSampleProducts,
        context: .lockedFeature(featureName: "AI Deep Dive")
    ))
}

#Preview("Already Pro — Apple subscription") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "com.chapterflow.ios.pro.annual", expirationDate: nil),
        products: previewSampleProducts,
        context: .settings,
        proSource: "apple"
    ))
}

#Preview("Already Pro — via web (Stripe)") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "", expirationDate: nil),
        products: previewSampleProducts,
        context: .settings,
        proSource: "stripe"
    ))
}

#Preview("Already Pro — via web · dark mode") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "", expirationDate: nil),
        products: previewSampleProducts,
        context: .settings,
        proSource: "stripe"
    ))
    .preferredColorScheme(.dark)
}

#Preview("Already Pro — via web · XXL text") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "", expirationDate: nil),
        products: previewSampleProducts,
        context: .settings,
        proSource: "stripe"
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Already Pro — license") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "", expirationDate: nil),
        products: previewSampleProducts,
        context: .settings,
        proSource: "license"
    ))
}

#Preview("Grace period") {
    PaywallView(model: previewPaywallModel(
        status: .inGracePeriod(productID: "com.chapterflow.ios.pro.annual", expirationDate: nil),
        products: previewSampleProducts
    ))
}

#Preview("Server benefits") {
    PaywallView(model: previewPaywallModelWithBenefits())
}

// MARK: - Intro offer eligible previews

#Preview("Intro offer eligible — Start Free Trial CTA") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: previewSampleProducts   // annual has introductoryOfferText set
    ))
}

#Preview("Intro offer NOT eligible — regular Subscribe CTA") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: previewIneligibleProducts
    ))
}

#Preview("Intro offer eligible · dark mode") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: previewSampleProducts))
        .preferredColorScheme(.dark)
}

#Preview("Intro offer eligible · XXL text") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: previewSampleProducts))
        .dynamicTypeSize(.accessibility3)
}

// MARK: - Win-back offer previews (lapsed subscribers)

#Preview("Win-back — expired subscriber, free trial offer") {
    PaywallView(model: previewPaywallModelWithWinBack(paymentMode: .freeTrial))
}

#Preview("Win-back — expired subscriber, paid offer") {
    PaywallView(model: previewPaywallModelWithWinBack(paymentMode: .payUpFront))
}

#Preview("Win-back · dark mode") {
    PaywallView(model: previewPaywallModelWithWinBack(paymentMode: .freeTrial))
        .preferredColorScheme(.dark)
}

#Preview("Win-back · XXL text") {
    PaywallView(model: previewPaywallModelWithWinBack(paymentMode: .freeTrial))
        .dynamicTypeSize(.accessibility3)
}

// MARK: - Dark / XXL baseline

#Preview("Dark mode") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: previewSampleProducts))
        .preferredColorScheme(.dark)
}

#Preview("XXL text") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: previewSampleProducts))
        .dynamicTypeSize(.accessibility3)
}

// MARK: - Preview helpers

/// Products with NO introductory offer text — simulates an ineligible user.
let previewIneligibleProducts: [StoreProductInfo] = [
    StoreProductInfo(
        id: "com.chapterflow.ios.pro.annual",
        displayName: "Annual",
        displayPrice: "$49.99",
        periodLabel: "year",
        isPopular: true,
        introductoryOfferText: nil,  // ineligible — no trial shown
        priceDecimalValue: 49.99
    ),
    StoreProductInfo(
        id: "com.chapterflow.ios.pro.monthly",
        displayName: "Monthly",
        displayPrice: "$5.99",
        periodLabel: "month",
        isPopular: false,
        priceDecimalValue: 5.99
    ),
]

let previewSampleProducts: [StoreProductInfo] = [
    StoreProductInfo(
        id: "com.chapterflow.ios.pro.annual",
        displayName: "Annual",
        displayPrice: "$49.99",
        periodLabel: "year",
        isPopular: true,
        introductoryOfferText: "7-day free trial",
        priceDecimalValue: 49.99
    ),
    StoreProductInfo(
        id: "com.chapterflow.ios.pro.monthly",
        displayName: "Monthly",
        displayPrice: "$5.99",
        periodLabel: "month",
        isPopular: false,
        priceDecimalValue: 5.99
    ),
]

private actor PaywallPreviewStoreKitService: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void> = AsyncStream { _ in }
    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus { .notSubscribed }
    func verifyCurrentEntitlements() async throws {}
    func currentTransactionID() async -> UInt64? { nil }
}

@MainActor
func previewPaywallModel(
    status: SubscriptionStatus,
    products: [StoreProductInfo],
    context: PaywallContext = .settings,
    proSource: String? = nil
) -> PaywallModel {
    let model = PaywallModel(
        storeKitService: PaywallPreviewStoreKitService(),
        apiClient: MockAPIClient(),
        context: context,
        initialProductInfos: products,
        initialStatus: status
    )
    if let proSource {
        model.inject(productInfos: products, status: status, proSource: proSource)
    }
    return model
}

@MainActor
private func previewPaywallModelWithWinBack(paymentMode: WinBackDisplayInfo.PaymentModeKind) -> PaywallModel {
    let winBack = WinBackDisplayInfo(
        productID: "com.chapterflow.ios.pro.annual",
        productDisplayName: "Annual Pro",
        offerDisplayPrice: paymentMode == .freeTrial ? "Free" : "$12.99",
        offerPeriodText: paymentMode == .freeTrial ? "7 days" : "3 months",
        regularDisplayPrice: "$49.99",
        regularPeriodLabel: "year",
        paymentMode: paymentMode,
        offerID: "win-back-preview"
    )
    let model = PaywallModel(
        storeKitService: PaywallPreviewStoreKitService(),
        apiClient: MockAPIClient(),
        context: .settings,
        initialProductInfos: previewSampleProducts,
        initialStatus: .expired(productID: "com.chapterflow.ios.pro.annual")
    )
    model.inject(
        productInfos: previewSampleProducts,
        status: .expired(productID: "com.chapterflow.ios.pro.annual"),
        winBackDisplay: winBack
    )
    return model
}

@MainActor
private func previewPaywallModelWithBenefits() -> PaywallModel {
    let model = previewPaywallModel(status: .notSubscribed, products: previewSampleProducts)
    model.inject(
        productInfos: previewSampleProducts,
        status: .notSubscribed,
        serverBenefits: [
            "Unlimited books from our full catalogue",
            "Offline reading — no internet required",
            "AI Deep Dive — ask any question about a book",
            "Unlimited spaced-repetition quizzes",
            "Highlights, notes & export"
        ]
    )
    return model
}
