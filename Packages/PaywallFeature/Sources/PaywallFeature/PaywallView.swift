import SwiftUI
import StoreKit
import Networking
import DesignSystem

// MARK: - PaywallView

/// The subscription upgrade sheet.
///
/// Shown whenever the user attempts a gated action or taps "Upgrade."
/// Prices and product names are always sourced from StoreKit (never
/// hardcoded) to comply with App Store guidelines and ensure correct
/// localisation.
public struct PaywallView: View {

    @State private var model: PaywallModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessOverlay = false

    public init(model: PaywallModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: .cfSpacing24) {
                        headerSection
                        if model.subscriptionStatus.isPro {
                            alreadyProSection
                        } else {
                            benefitsSection
                            if model.isLoadingProducts {
                                productsLoadingSection
                            } else if !model.productInfos.isEmpty {
                                productsSection
                            }
                            if let error = model.errorMessage {
                                Text(error)
                                    .font(.cfCaption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.cfSpacing8)
                            }
                            ctaSection
                        }
                        footerSection
                    }
                    .padding(.horizontal, .cfSpacing20)
                    .padding(.vertical, .cfSpacing32)
                }
                .background(Color.cfGroupedBackground)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.cfTertiaryLabel)
                                .font(.title3)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                }
            }

            if showSuccessOverlay {
                successOverlayView
            }
        }
        .task {
            await model.onAppear()
            model.startListening()
        }
        .onChange(of: model.purchaseState) { _, newState in
            if case .success = newState {
                showSuccessOverlay = true
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text(model.context.headline)
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text(model.context.subtitle)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Already Pro

    private var alreadyProSection: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text("You're already a Pro member")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            billingStatusBanner

            Button {
                model.openManageSubscriptions()
            } label: {
                Text("Manage Subscription")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .accessibilityLabel("Manage Subscription — opens App Store")
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    // MARK: - Benefits

    @ViewBuilder
    private var benefitsSection: some View {
        if let serverBenefits = model.serverBenefits {
            VStack(alignment: .leading, spacing: .cfSpacing12) {
                ForEach(serverBenefits, id: \.self) { benefit in
                    HStack(spacing: .cfSpacing12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.cfAccent)
                            .frame(width: .cfIconSmall)
                            .accessibilityHidden(true)
                        Text(benefit)
                            .font(.cfHeadline)
                            .foregroundStyle(Color.cfLabel)
                    }
                }
            }
            .padding(.cfSpacing16)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        } else {
            VStack(alignment: .leading, spacing: .cfSpacing12) {
                ForEach(ProBenefit.allCases, id: \.self) { benefit in
                    HStack(spacing: .cfSpacing12) {
                        Image(systemName: benefit.iconName)
                            .foregroundStyle(Color.cfAccent)
                            .frame(width: .cfIconSmall)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.cfHeadline)
                                .foregroundStyle(Color.cfLabel)
                            Text(benefit.subtitle)
                                .font(.cfFootnote)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                    }
                }
            }
            .padding(.cfSpacing16)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        }
    }

    // MARK: - Products

    private var productsLoadingSection: some View {
        VStack(spacing: .cfSpacing12) {
            ForEach(0..<2, id: \.self) { _ in
                CFSkeleton()
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
            }
        }
    }

    private var productsSection: some View {
        VStack(spacing: .cfSpacing12) {
            ForEach(model.productInfos) { info in
                ProductOptionRow(
                    info: info,
                    isSelected: model.selectedProductID == info.id,
                    savingsPercent: info.periodLabel == "year" ? model.annualSavingsPercent : nil
                ) {
                    model.selectProduct(info.id)
                }
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                guard let id = model.selectedProductID else { return }
                Task { await model.purchase(productID: id) }
            } label: {
                Group {
                    if model.purchaseState == .purchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.cfHeadline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(model.purchaseState.isInProgress || model.selectedProductID == nil)
            .accessibilityLabel(ctaTitle)

            billingStatusBanner
        }
    }

    private var ctaTitle: String {
        switch model.purchaseState {
        case .purchasing:       return "Processing…"
        case .restoring:        return "Restoring…"
        case .pendingApproval:  return "Awaiting Approval"
        case .success:          return "Welcome to Pro!"
        case .idle, .failed:
            if let id = model.selectedProductID,
               let info = model.productInfos.first(where: { $0.id == id }) {
                return "Subscribe – \(info.displayPrice) / \(info.periodLabel)"
            }
            return "Subscribe"
        }
    }

    // MARK: - Billing status banner

    @ViewBuilder
    private var billingStatusBanner: some View {
        switch model.subscriptionStatus {
        case .inGracePeriod:
            statusBanner(
                icon: "exclamationmark.triangle.fill",
                text: "Payment failed — update your payment method to keep Pro.",
                tint: .orange
            )
        case .inBillingRetry:
            statusBanner(
                icon: "creditcard.trianglebadge.exclamationmark",
                text: "We're having trouble billing you. Update your payment method.",
                tint: .red
            )
        case .pending:
            statusBanner(
                icon: "clock.fill",
                text: "Your purchase is awaiting approval.",
                tint: .yellow
            )
        default:
            EmptyView()
        }
    }

    private func statusBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.cfCaption)
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.cfSpacing12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: .cfSpacing8) {
            if !model.subscriptionStatus.isPro {
                Button {
                    Task { await model.restorePurchases() }
                } label: {
                    Text(model.purchaseState == .restoring ? "Restoring…" : "Restore Purchases")
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfAccent)
                }
                .disabled(model.purchaseState.isInProgress)
                .accessibilityLabel("Restore previous purchases")
            }

            HStack(spacing: .cfSpacing16) {
                if let termsURL = URL(string: "https://chapterflow.app/terms") {
                    Link("Terms of Service", destination: termsURL)
                }
                if let privacyURL = URL(string: "https://chapterflow.app/privacy") {
                    Link("Privacy Policy", destination: privacyURL)
                }
            }
            .font(.cfCaption)
            .foregroundStyle(Color.cfTertiaryLabel)

            Text("Subscriptions renew automatically. Cancel any time in Settings → Apple ID → Subscriptions.")
                .font(.cfCaption2)
                .foregroundStyle(Color.cfTertiaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Success overlay

    private var successOverlayView: some View {
        ZStack {
            Color.cfGroupedBackground
                .opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: .cfSpacing24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityHidden(true)

                Text("You're Pro!")
                    .font(.cfLargeTitle)
                    .foregroundStyle(Color.cfLabel)

                Text("Your subscription is active. Enjoy unlimited access.")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .cfSpacing32)
            }

            CFConfetti(isActive: showSuccessOverlay)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Purchase successful. You're now a Pro member.")
    }
}

// MARK: - ProductOptionRow

private struct ProductOptionRow: View {
    let info: StoreProductInfo
    let isSelected: Bool
    let savingsPercent: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: .cfSpacing12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.cfAccent : Color.cfTertiaryLabel)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: .cfSpacing8) {
                        Text(info.displayName)
                            .font(.cfHeadline)
                            .foregroundStyle(Color.cfLabel)
                        if info.isPopular {
                            Text("Popular")
                                .font(.cfCaption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, .cfSpacing8)
                                .padding(.vertical, 2)
                                .background(Color.cfAccent, in: Capsule())
                        }
                        if let pct = savingsPercent, pct > 0 {
                            Text("Save \(pct)%")
                                .font(.cfCaption2)
                                .foregroundStyle(Color.cfAccent)
                                .padding(.horizontal, .cfSpacing8)
                                .padding(.vertical, 2)
                                .background(Color.cfAccent.opacity(0.12), in: Capsule())
                        }
                    }
                    if let intro = info.introductoryOfferText {
                        Text(intro)
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfAccent)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(info.displayPrice)
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                    Text("/ \(info.periodLabel)")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            .padding(.cfSpacing16)
            .background(
                RoundedRectangle(cornerRadius: .cfRadius16)
                    .fill(Color.cfSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: .cfRadius16)
                            .strokeBorder(
                                isSelected ? Color.cfAccent : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(info.displayName), \(info.displayPrice) per \(info.periodLabel)" +
            (info.isPopular ? ", popular" : "") +
            (savingsPercent.map { ", save \($0) percent" } ?? "")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - ProBenefit

private enum ProBenefit: CaseIterable {
    case unlimitedBooks, offlineReading, aiInsights, quizzes, notes

    var iconName: String {
        switch self {
        case .unlimitedBooks:  return "books.vertical.fill"
        case .offlineReading:  return "arrow.down.circle.fill"
        case .aiInsights:      return "sparkles"
        case .quizzes:         return "checkmark.seal.fill"
        case .notes:           return "note.text"
        }
    }

    var title: String {
        switch self {
        case .unlimitedBooks:  return "Unlimited Books"
        case .offlineReading:  return "Offline Reading"
        case .aiInsights:      return "AI Insights"
        case .quizzes:         return "Unlimited Quizzes"
        case .notes:           return "Highlights & Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .unlimitedBooks:  return "Access the full catalogue of 200+ books"
        case .offlineReading:  return "Download books and read without internet"
        case .aiInsights:      return "Ask the book, concept graphs, deep analysis"
        case .quizzes:         return "Reinforce every chapter with spaced repetition"
        case .notes:           return "Save highlights and personal reflections"
        }
    }
}

// MARK: - Previews

#Preview("Default — not subscribed", traits: .sizeThatFitsLayout) {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: []))
        .frame(maxHeight: 700)
}

#Preview("With products — settings context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: sampleProducts,
        context: .settings
    ))
}

#Preview("Book detail context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: sampleProducts,
        context: .bookDetail(bookTitle: "Atomic Habits")
    ))
}

#Preview("Locked feature context") {
    PaywallView(model: previewPaywallModel(
        status: .notSubscribed,
        products: sampleProducts,
        context: .lockedFeature(featureName: "AI Deep Dive")
    ))
}

#Preview("Already Pro") {
    PaywallView(model: previewPaywallModel(
        status: .subscribed(productID: "com.chapterflow.ios.pro.annual", expirationDate: nil),
        products: sampleProducts,
        context: .settings
    ))
}

#Preview("Grace period") {
    PaywallView(model: previewPaywallModel(
        status: .inGracePeriod(productID: "com.chapterflow.ios.pro.annual", expirationDate: nil),
        products: sampleProducts
    ))
}

#Preview("Server benefits") {
    PaywallView(model: previewPaywallModelWithBenefits())
}

#Preview("Dark mode") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: sampleProducts))
        .preferredColorScheme(.dark)
}

#Preview("XXL text") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: sampleProducts))
        .dynamicTypeSize(.accessibility3)
}

// MARK: - Preview helpers

private let sampleProducts: [StoreProductInfo] = [
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

private actor PreviewStoreKitService: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void> = AsyncStream { _ in }
    func loadProducts() async throws -> [StoreKit.Product] { [] }
    func purchase(_ product: StoreKit.Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus { .notSubscribed }
}

@MainActor
private func previewPaywallModel(
    status: SubscriptionStatus,
    products: [StoreProductInfo],
    context: PaywallContext = .settings
) -> PaywallModel {
    PaywallModel(
        storeKitService: PreviewStoreKitService(),
        apiClient: MockAPIClient(),
        context: context,
        initialProductInfos: products,
        initialStatus: status
    )
}

@MainActor
private func previewPaywallModelWithBenefits() -> PaywallModel {
    let model = previewPaywallModel(status: .notSubscribed, products: sampleProducts)
    model.inject(
        productInfos: sampleProducts,
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
