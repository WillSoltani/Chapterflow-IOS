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
    @State private var selectedProductID: String?

    public init(model: PaywallModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    headerSection
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
        .task {
            await model.loadProducts()
            if selectedProductID == nil {
                selectedProductID = model.productInfos.first?.id
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

            Text("ChapterFlow Pro")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text("Read smarter. Learn more. Own your knowledge.")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
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
                    isSelected: selectedProductID == info.id
                ) {
                    selectedProductID = info.id
                }
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                guard let id = selectedProductID else { return }
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
            .disabled(model.purchaseState.isInProgress || selectedProductID == nil)
            .accessibilityLabel(ctaTitle)

            billingStatusBanner
        }
    }

    private var ctaTitle: String {
        switch model.purchaseState {
        case .purchasing:       return "Processing…"
        case .restoring:        return "Restoring…"
        case .pendingApproval:  return "Awaiting Approval"
        case .idle, .failed:
            if let id = selectedProductID,
               let info = model.productInfos.first(where: { $0.id == id }) {
                return "Subscribe – \(info.displayPrice) / \(info.periodLabel)"
            }
            return "Subscribe"
        }
    }

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
            Button {
                Task { await model.restorePurchases() }
            } label: {
                Text(model.purchaseState == .restoring ? "Restoring…" : "Restore Purchases")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfAccent)
            }
            .disabled(model.purchaseState.isInProgress)

            Text("Subscriptions renew automatically. Cancel any time in Settings → Apple ID → Subscriptions.")
                .font(.cfCaption2)
                .foregroundStyle(Color.cfTertiaryLabel)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - ProductOptionRow

private struct ProductOptionRow: View {
    let info: StoreProductInfo
    let isSelected: Bool
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
            (info.isPopular ? ", popular" : "")
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

#Preview("Default", traits: .sizeThatFitsLayout) {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: []))
        .frame(maxHeight: 700)
}

#Preview("With products") {
    PaywallView(model: previewPaywallModel(status: .notSubscribed, products: sampleProducts))
}

#Preview("Grace period") {
    PaywallView(model: previewPaywallModel(
        status: .inGracePeriod(productID: "com.cf.annual", expirationDate: nil),
        products: sampleProducts
    ))
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
        introductoryOfferText: "7-day free trial"
    ),
    StoreProductInfo(
        id: "com.chapterflow.ios.pro.monthly",
        displayName: "Monthly",
        displayPrice: "$5.99",
        periodLabel: "month",
        isPopular: false
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
    products: [StoreProductInfo]
) -> PaywallModel {
    PaywallModel(
        storeKitService: PreviewStoreKitService(),
        apiClient: MockAPIClient(),
        initialProductInfos: products,
        initialStatus: status
    )
}
