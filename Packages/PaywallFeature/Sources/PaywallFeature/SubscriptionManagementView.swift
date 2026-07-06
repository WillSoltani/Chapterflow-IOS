import SwiftUI
import StoreKit
import DesignSystem
import CoreKit

// MARK: - SubscriptionManagementView

/// Full subscription management screen.
///
/// Surfaces the user's current plan, billing source, renewal/expiry dates,
/// and auto-renew state. Routes each billing source to the correct management
/// destination:
/// - **Apple** — `.manageSubscriptionsSheet` + in-app refund request.
/// - **Stripe** — clear web-redirect guidance (chapterflow.ca).
/// - **License / Gift / Admin** — informational; no self-serve management in-app.
///
/// Handles billing-lifecycle states (grace period, billing retry, expired,
/// revoked) with honest messaging and a recovery path (resubscribe or update
/// payment). Price-increase consent messages are intercepted and displayed by
/// `SubscriptionManagementModel`.
public struct SubscriptionManagementView: View {

    @State private var model: SubscriptionManagementModel
    @Environment(\.dismiss) private var dismiss
    let onShowPaywall: (() -> Void)?

    public init(model: SubscriptionManagementModel, onShowPaywall: (() -> Void)? = nil) {
        self._model = State(initialValue: model)
        self.onShowPaywall = onShowPaywall
    }

    public var body: some View {
        NavigationStack {
            List {
                planHeaderSection
                billingAttentionSection
                detailsSection
                actionsSection
                recoverySection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss subscription management")
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.isLoading {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.onAppear() }
        }
        #if os(iOS)
        // System sheet: Manage App Store subscriptions
        .manageSubscriptionsSheet(isPresented: $model.showManageSubscriptionsSheet)
        // In-app refund request sheet
        .refundRequestSheet(
            for: model.activeTransactionID ?? 0,
            isPresented: $model.showRefundSheet,
            onDismiss: { @MainActor result in
                model.handleRefundResult(result)
            }
        )
        #endif
        .alert(refundAlertTitle, isPresented: Binding(
            get: { showRefundAlert },
            set: { if !$0 { model.resetRefundOutcome() } }
        )) {
            Button("OK", role: .cancel) { model.resetRefundOutcome() }
        } message: {
            Text(refundAlertMessage)
        }
    }

    // MARK: - Plan header section

    private var planHeaderSection: some View {
        Section {
            PlanHeaderRow(state: model.detailState)
        }
    }

    // MARK: - Billing attention banner

    @ViewBuilder
    private var billingAttentionSection: some View {
        if model.detailState.requiresBillingAttention {
            Section {
                BillingAttentionBanner(state: model.detailState) {
                    model.manageAppleSubscription()
                }
            }
        }
    }

    // MARK: - Details section (dates, source details)

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            switch model.detailState {
            case .appleActive(_, let renewsAt):
                dateRow(label: "Renews", date: renewsAt)
                autoRenewRow(autoRenews: true)
            case .applyCancelling(_, let expiresAt):
                dateRow(label: "Cancels", date: expiresAt, tint: .orange)
                autoRenewRow(autoRenews: false)
            case .appleGracePeriod(_, let expiresAt):
                dateRow(label: "Grace period ends", date: expiresAt, tint: .orange)
                autoRenewRow(autoRenews: true)
            case .appleBillingRetry(let pid):
                sourceRow(source: .apple, detail: pid.isEmpty ? nil : pid)
            case .appleExpired(let pid):
                sourceRow(source: .apple, detail: pid.isEmpty ? nil : pid)
            case .appleRevoked, .applePending:
                sourceRow(source: .apple)
            case .stripeActive(let renewsAt, let cancels):
                dateRow(label: cancels ? "Cancels" : "Renews", date: renewsAt, tint: cancels ? .orange : nil)
                autoRenewRow(autoRenews: !cancels)
            case .stripePastDue(let renewsAt):
                dateRow(label: "Billing paused since", date: renewsAt, tint: .red)
            case .licenseActive(let key, let expiresAt):
                if let key {
                    LabeledContent("License Key", value: key)
                        .font(.cfBody)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("License key: \(key)")
                }
                dateRow(label: "Expires", date: expiresAt)
            case .giftActive(let expiresAt):
                dateRow(label: "Gift expires", date: expiresAt)
            case .adminOrOther(let source, let expiresAt):
                LabeledContent("Source", value: source.capitalized)
                    .font(.cfBody)
                dateRow(label: "Expires", date: expiresAt)
            case .free:
                EmptyView()
            }
        }
    }

    // MARK: - Actions section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            switch model.detailState {
            case .appleActive, .appleGracePeriod, .appleBillingRetry, .applePending:
                manageAppleButton
                if model.activeTransactionID != nil {
                    requestRefundButton
                }
            case .applyCancelling:
                manageAppleButton
                resubscribeButton
                if model.activeTransactionID != nil {
                    requestRefundButton
                }
            case .appleExpired, .appleRevoked:
                resubscribeButton
            case .stripeActive:
                manageStripeButton()
            case .stripePastDue:
                manageStripeButton(label: "Update Payment Method")
            case .licenseActive:
                manageLicenseInfo
            case .giftActive, .adminOrOther, .free:
                EmptyView()
            }
        }
    }

    // MARK: - Recovery section (for expired/revoked)

    @ViewBuilder
    private var recoverySection: some View {
        switch model.detailState {
        case .appleExpired, .appleRevoked:
            Section {
                Text("Your previous subscription has ended. Subscribe again to restore Pro access.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        case .stripePastDue:
            Section {
                Text("Your payment method needs attention. Update it at chapterflow.ca to keep your Pro access.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Reusable row helpers

    @ViewBuilder
    private func dateRow(label: String, date: Date?, tint: Color? = nil) -> some View {
        if let date {
            HStack {
                Text(label)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(tint ?? Color.cfSecondaryLabel)
            }
            .font(.cfBody)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(date.formatted(date: .long, time: .omitted))")
        }
    }

    private func autoRenewRow(autoRenews: Bool) -> some View {
        HStack {
            Text("Auto-Renew")
                .foregroundStyle(Color.cfLabel)
            Spacer()
            Text(autoRenews ? "On" : "Off")
                .foregroundStyle(autoRenews ? Color.cfAccent : Color.orange)
        }
        .font(.cfBody)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Auto-renew: \(autoRenews ? "on" : "off")")
    }

    private func sourceRow(source: ProSourceKind, detail: String? = nil) -> some View {
        HStack {
            Text("Source")
                .foregroundStyle(Color.cfLabel)
            Spacer()
            Text(detail ?? source.displayName)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .font(.cfBody)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subscription source: \(source.displayName)")
    }

    // MARK: - Action buttons

    private var manageAppleButton: some View {
        Button {
            model.manageAppleSubscription()
        } label: {
            HStack {
                Label("Manage Subscription", systemImage: "creditcard")
                    .foregroundStyle(Color.cfAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage subscription in the App Store")
        .accessibilityHint("Opens App Store subscription management")
    }

    private var resubscribeButton: some View {
        Button {
            dismiss()
            onShowPaywall?()
        } label: {
            Label("Resubscribe to Pro", systemImage: "crown")
                .foregroundStyle(Color.cfAccent)
        }
        .accessibilityLabel("Resubscribe to ChapterFlow Pro")
        .accessibilityHint("Opens the subscription screen")
    }

    private var requestRefundButton: some View {
        Button {
            model.requestRefund()
        } label: {
            Label("Request a Refund", systemImage: "arrow.uturn.backward.circle")
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .accessibilityLabel("Request a refund for your subscription")
        .accessibilityHint("Opens an Apple refund request")
    }

    private func manageStripeButton(label: String = "Manage on Web") -> some View {
        Link(destination: URL(string: "https://chapterflow.ca/account/billing")!) {
            HStack {
                Label(label, systemImage: "globe")
                    .foregroundStyle(Color.cfAccent)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .accessibilityLabel("\(label) — opens chapterflow.ca in your browser")
    }

    private var manageLicenseInfo: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Label("License Management", systemImage: "key.horizontal")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Text("To renew or transfer your license, visit chapterflow.ca/account.")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("License management: visit chapterflow.ca/account to renew or transfer.")
    }

    // MARK: - Refund alert

    private var showRefundAlert: Bool {
        switch model.refundOutcome {
        case .success, .failed: return true
        case .idle, .userCancelled: return false
        }
    }

    private var refundAlertTitle: String {
        if case .success = model.refundOutcome { return "Refund Requested" }
        return "Refund Unavailable"
    }

    private var refundAlertMessage: String {
        switch model.refundOutcome {
        case .success:
            return "Your refund request has been submitted. Apple will email you with the outcome."
        case .failed(let msg):
            return msg
        case .idle, .userCancelled:
            return ""
        }
    }
}

// MARK: - Plan Header Row

private struct PlanHeaderRow: View {
    let state: SubscriptionDetailState

    var body: some View {
        HStack(spacing: .cfSpacing12) {
            // Source icon
            Image(systemName: iconName)
                .font(.system(size: 28))
                .foregroundStyle(iconColor)
                .frame(width: .cfIconLarge, height: .cfIconLarge)
                .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: .cfRadius12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(planLabel)
                    .font(.cfTitle3.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)

                Text(sourceLabel)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }

            Spacer()

            // Status chip
            Text(statusChipLabel)
                .font(.cfCaption.weight(.semibold))
                .foregroundStyle(statusChipForeground)
                .padding(.horizontal, .cfSpacing8)
                .padding(.vertical, .cfSpacing4)
                .background(statusChipBackground, in: Capsule())
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(planLabel) — \(sourceLabel) — Status: \(statusChipLabel)")
    }

    private var iconName: String {
        switch state {
        case .appleActive, .applyCancelling, .appleGracePeriod,
             .appleBillingRetry, .applePending:
            return "apple.logo"
        case .appleExpired, .appleRevoked:
            return "xmark.circle"
        case .stripeActive, .stripePastDue:
            return "globe"
        case .licenseActive:
            return "key.horizontal"
        case .giftActive:
            return "gift"
        case .adminOrOther:
            return "shield.lefthalf.filled"
        case .free:
            return "books.vertical"
        }
    }

    private var iconColor: Color {
        switch state {
        case .appleGracePeriod, .appleBillingRetry, .stripePastDue: return .orange
        case .appleExpired, .appleRevoked: return Color.cfSecondaryLabel
        case .free: return Color.cfSecondaryLabel
        default: return Color.cfAccent
        }
    }

    private var planLabel: String {
        state.isPro ? "ChapterFlow Pro" : "ChapterFlow Free"
    }

    private var sourceLabel: String {
        switch state {
        case .appleActive:         return "Apple subscription"
        case .applyCancelling:     return "Apple subscription"
        case .appleGracePeriod:    return "Apple subscription"
        case .appleBillingRetry:   return "Apple subscription"
        case .appleExpired:        return "Apple subscription (expired)"
        case .appleRevoked:        return "Apple subscription (refunded)"
        case .applePending:        return "Apple subscription"
        case .stripeActive:        return "Web subscription"
        case .stripePastDue:       return "Web subscription"
        case .licenseActive:       return "License"
        case .giftActive:          return "Gift"
        case .adminOrOther(let s, _): return s.capitalized
        case .free:                return "No active subscription"
        }
    }

    private var statusChipLabel: String {
        switch state {
        case .appleActive:         return "Active"
        case .applyCancelling:     return "Cancelling"
        case .appleGracePeriod:    return "Grace Period"
        case .appleBillingRetry:   return "Payment Issue"
        case .appleExpired:        return "Expired"
        case .appleRevoked:        return "Refunded"
        case .applePending:        return "Pending"
        case .stripeActive(_, let cancels):
            return cancels ? "Cancelling" : "Active"
        case .stripePastDue:       return "Past Due"
        case .licenseActive:       return "Active"
        case .giftActive:          return "Active"
        case .adminOrOther:        return "Active"
        case .free:                return "Free"
        }
    }

    private var statusChipForeground: Color {
        switch state {
        case .appleGracePeriod, .appleBillingRetry, .stripePastDue: return .orange
        case .appleExpired, .appleRevoked: return Color.cfSecondaryLabel
        case .applyCancelling, .stripeActive(_, true): return .orange
        case .free: return Color.cfSecondaryLabel
        default: return Color.cfAccent
        }
    }

    private var statusChipBackground: Color {
        statusChipForeground.opacity(0.12)
    }
}

// MARK: - Billing Attention Banner

private struct BillingAttentionBanner: View {
    let state: SubscriptionDetailState
    let onManage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(bannerColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(title)
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                Text(bannerMessage)
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if showManageCTA {
                    Button(action: onManage) {
                        Text("Update Payment Method")
                            .font(.cfFootnote.weight(.semibold))
                            .foregroundStyle(bannerColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, .cfSpacing4)
                    .accessibilityLabel("Update payment method in the App Store")
                }
            }
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(bannerMessage)")
    }

    private var iconName: String {
        switch state {
        case .appleGracePeriod:  return "exclamationmark.triangle.fill"
        case .appleBillingRetry: return "creditcard.trianglebadge.exclamationmark"
        case .stripePastDue:     return "exclamationmark.triangle.fill"
        default:                 return "exclamationmark.circle"
        }
    }

    private var bannerColor: Color {
        switch state {
        case .appleBillingRetry: return .red
        default: return .orange
        }
    }

    private var title: String {
        switch state {
        case .appleGracePeriod:
            return "Payment Failed"
        case .appleBillingRetry:
            return "Billing Unavailable"
        case .stripePastDue:
            return "Payment Overdue"
        default:
            return "Attention Required"
        }
    }

    private var bannerMessage: String {
        switch state {
        case .appleGracePeriod:
            return "Your payment failed. Apple will retry billing before your grace period ends. Update your payment method to keep Pro access."
        case .appleBillingRetry:
            return "Your grace period has ended and billing is still failing. Update your payment method immediately to restore full Pro access."
        case .stripePastDue:
            return "Your Stripe payment could not be processed. Update your payment method at chapterflow.ca to restore Pro access."
        default:
            return "Your subscription requires attention."
        }
    }

    private var showManageCTA: Bool {
        switch state {
        case .appleGracePeriod, .appleBillingRetry: return true
        default: return false
        }
    }
}
