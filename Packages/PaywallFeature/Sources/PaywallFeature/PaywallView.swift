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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSuccessOverlay = false
    let performsInitialLoad: Bool
    private let reduceMotionOverride: Bool?

    public init(model: PaywallModel) {
        self._model = State(initialValue: model)
        self.performsInitialLoad = true
        self.reduceMotionOverride = nil
    }

    init(
        previewModel model: PaywallModel,
        showSuccessOverlay: Bool = false,
        reduceMotionOverride: Bool? = nil
    ) {
        self._model = State(initialValue: model)
        self._showSuccessOverlay = State(initialValue: showSuccessOverlay)
        self.performsInitialLoad = false
        self.reduceMotionOverride = reduceMotionOverride
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: .cfSpacing24) {
                        headerSection
                        if model.entitlementResolution == .resolvedPro
                            || model.subscriptionStatus.isPro {
                            alreadyProSection
                        } else {
                            benefitsSection
                            entitlementAwareOfferSection
                            if let error = model.errorMessage {
                                Text(error)
                                    .font(.cfCaption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.cfSpacing8)
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
            .accessibilityHidden(showSuccessOverlay)

            if showSuccessOverlay {
                PaywallSuccessOverlay(
                    isActive: showSuccessOverlay,
                    reduceMotion: reduceMotionOverride ?? reduceMotion
                ) {
                    dismiss()
                }
            }
        }
        .task {
            guard performsInitialLoad else { return }
            await model.onAppear()
            model.startListening()
        }
        .onChange(of: model.purchaseState) { _, newState in
            if case .success = newState {
                showSuccessOverlay = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text(model.context.headline)
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

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
                .font(.system(size: .cfIconLarge))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text("You're already a Pro member")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)
                .accessibilityLabel("You are a Pro member via \(sourceKind.displayName).")

            if sourceKind.isApple {
                // Apple subscription: surface billing lifecycle banners + manage in App Store.
                billingStatusBanner

                Button {
                    model.openManageSubscriptions()
                } label: {
                    Text("Manage Subscription")
                        .font(.cfHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: .cfSpacing48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cfAccent)
                .accessibilityLabel("Manage Subscription — opens App Store")
            } else if sourceKind == .unknown {
                Text("Your Pro access is active.")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)

                Text("We're confirming where this membership is managed. Try again shortly.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .multilineTextAlignment(.center)
            } else {
                // Non-Apple source (Stripe, license, gift, etc.): explain where to manage.
                Text("Your Pro access comes from \(sourceKind.displayName).")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)

                Text("To manage or cancel, visit app.chapterflow.ca from any browser.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .accessibilityElement(children: .contain)
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

    @ViewBuilder
    private var entitlementAwareOfferSection: some View {
        switch model.entitlementResolution {
        case .unresolved, .resolving:
            membershipCheckLoadingSection
        case .unavailable:
            membershipCheckUnavailableSection
        case .resolvedFree:
            if let winBack = model.winBackDisplay, model.subscriptionStatus.isLapsed {
                winBackSection(winBack)
            } else if model.productAvailability == .loading {
                productsLoadingSection
            } else if model.productAvailability == .available,
                      !model.productInfos.isEmpty {
                productsSection
                ctaSection
            } else if model.productAvailability != .idle {
                productsUnavailableSection
            }
        case .resolvedPro:
            EmptyView()
        }
    }

    private var membershipCheckLoadingSection: some View {
        VStack(spacing: .cfSpacing12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.cfAccent)
                .accessibilityHidden(true)
            Text("Checking your membership…")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text("Subscription options will appear after we confirm this account's current access.")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your current ChapterFlow membership")
    }

    private var membershipCheckUnavailableSection: some View {
        CFEmptyState(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "Membership Check Unavailable",
            description: "We couldn't confirm this account's current access. Check your connection and try again.",
            actionLabel: "Try Again"
        ) {
            Task { await model.refreshEntitlement() }
        }
        .accessibilityElement(children: .contain)
    }

    private var productsLoadingSection: some View {
        VStack(spacing: .cfSpacing12) {
            ForEach(0..<2, id: \.self) { _ in
                CFSkeleton()
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading subscription options")
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

    private var productsUnavailableSection: some View {
        PaywallProductsUnavailableView(availability: model.productAvailability) {
            Task { await model.loadProducts() }
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
                .frame(minHeight: .cfSpacing48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(!model.canPurchase)
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
        case .confirmingAccess: return "Confirming Pro Access…"
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
                .disabled(purchaseActionsDisabled)
                .accessibilityLabel("Restore previous purchases")

            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: .cfSpacing16) {
                    legalLinks
                }
                VStack(spacing: .cfSpacing8) {
                    legalLinks
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

    @ViewBuilder
    private var legalLinks: some View {
        if let termsURL = URL(string: "https://app.chapterflow.ca/terms") {
            Link("Terms of Service", destination: termsURL)
        }
        if let privacyURL = URL(string: "https://app.chapterflow.ca/privacy") {
            Link("Privacy Policy", destination: privacyURL)
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
                .frame(minHeight: .cfSpacing48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(purchaseActionsDisabled)
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
        case .confirmingAccess: return "Confirming Pro Access…"
        case .success: return "Welcome back!"
        default:
            switch info.paymentMode {
            case .freeTrial: return "Claim Free Trial"
            case .payUpFront, .payAsYouGo: return "Claim Offer – \(info.offerDisplayPrice)"
            }
        }
    }

    private var purchaseActionsDisabled: Bool {
        switch model.purchaseState {
        case .purchasing, .restoring, .pendingApproval, .confirmingAccess, .success:
            return true
        case .idle, .failed:
            return false
        }
    }
}
