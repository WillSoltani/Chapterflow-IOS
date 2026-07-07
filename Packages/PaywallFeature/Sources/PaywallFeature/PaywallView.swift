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
                            if let winBack = model.winBackDisplay, model.subscriptionStatus.isLapsed {
                                winBackSection(winBack)
                            } else {
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
        #if os(iOS)
        .offerCodeRedemption(isPresented: Bindable(model).showOfferCodeRedemption) { _ in
            // Resulting transaction flows through Transaction.updates in StoreKitService,
            // which posts to the backend and fires entitlementChanges automatically.
        }
        #endif
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
        let sourceKind = ProSourceKind(rawSource: model.proSource)
        return VStack(spacing: .cfSpacing16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text("You're already a Pro member")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            if sourceKind.isApple {
                // Apple subscription: surface billing lifecycle banners + manage in App Store.
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
            } else {
                // Non-Apple source (Stripe, license, gift, etc.): explain where to manage.
                Text("Your Pro access comes from your \(sourceKind.displayName) subscription.")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)

                Text("To manage or cancel, visit chapterflow.app from any browser.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are a Pro member via \(sourceKind.displayName).")
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

            introTrialDisclosure

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
                if info.introductoryOfferText != nil {
                    return "Start Free Trial"
                }
                return "Subscribe – \(info.displayPrice) / \(info.periodLabel)"
            }
            return "Subscribe"
        }
    }

    /// Introductory offer disclosure shown below the CTA when the selected product
    /// has a trial/intro offer the current user is eligible for.
    @ViewBuilder
    private var introTrialDisclosure: some View {
        if let id = model.selectedProductID,
           let info = model.productInfos.first(where: { $0.id == id }),
           let introText = info.introductoryOfferText {
            Text("\(introText), then \(info.displayPrice)/\(info.periodLabel). Cancel any time.")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
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

                Button {
                    model.redeemOfferCode()
                } label: {
                    Text("Redeem Offer Code")
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfAccent)
                }
                .accessibilityLabel("Redeem a promotional offer code")
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

    // MARK: - Win-back section

    private func winBackSection(_ winBack: WinBackDisplayInfo) -> some View {
        VStack(spacing: .cfSpacing16) {
            VStack(spacing: .cfSpacing8) {
                Text("Welcome back, \(winBack.productDisplayName)")
                    .font(.cfTitle3)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)

                Text("We'd love to have you back. Here's a special offer:")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)

                Text(winBack.fullDescription)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfAccent)
                    .multilineTextAlignment(.center)
            }
            .padding(.cfSpacing16)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))

            Button {
                Task { await model.purchaseWinBack() }
            } label: {
                Group {
                    if model.purchaseState == .purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(winBackCTATitle(winBack))
                            .font(.cfHeadline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(model.purchaseState.isInProgress)
            .accessibilityLabel(winBackCTATitle(winBack))

            Text("Renews at \(winBack.regularDisplayPrice)/\(winBack.regularPeriodLabel) after offer ends. Cancel any time.")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    private func winBackCTATitle(_ info: WinBackDisplayInfo) -> String {
        switch model.purchaseState {
        case .purchasing: return "Processing…"
        case .pendingApproval: return "Awaiting Approval"
        case .success: return "Welcome back!"
        default:
            switch info.paymentMode {
            case .freeTrial: return "Claim Free Trial"
            case .payUpFront, .payAsYouGo: return "Claim Offer – \(info.offerDisplayPrice)"
            }
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
        case .quizzes:         return "checkmark.circle.fill"
        case .notes:           return "pencil.and.outline"
        }
    }

    var title: String {
        switch self {
        case .unlimitedBooks:  return "Unlimited Books"
        case .offlineReading:  return "Offline Reading"
        case .aiInsights:      return "AI Deep Dive"
        case .quizzes:         return "Spaced-Repetition Quizzes"
        case .notes:           return "Highlights & Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .unlimitedBooks:  return "Access our full catalogue of titles"
        case .offlineReading:  return "Read anywhere — no internet required"
        case .aiInsights:      return "Ask anything about any book"
        case .quizzes:         return "Retain what you read, long-term"
        case .notes:           return "Capture insights and export them"
        }
    }
}
