import SwiftUI
import DesignSystem
import NotificationsFeature

/// The Settings tab.
///
/// Shows the user's current subscription plan, upgrade or manage-subscription
/// options, and general app preferences. Keeps subscription upgrade prompts
/// non-intrusive — they are informational rows, not modal banners.
///
/// All subscription state is injected from `AppFeature` via `EntitlementService`;
/// SettingsFeature itself has no StoreKit dependency.
public struct SettingsView: View {

    private let isPro: Bool
    private let remainingFreeStarts: Int
    private let currentPeriodEnd: Date?
    private let cancelAtPeriodEnd: Bool?
    private let onShowPaywall: (() -> Void)?
    private let onManageSubscription: (() -> Void)?
    private let pushStatus: NotificationPermissionStatus?
    private let pushRegistrationError: Error?
    private let onManagePushSettings: (() -> Void)?
    /// Called when the user taps "Privacy Settings" — navigate to
    /// ``PrivacySettingsView`` in your feature's navigation stack.
    private let onShowPrivacySettings: (() -> Void)?
    private let notificationSettingsModel: NotificationSettingsModel?

    public init(
        isPro: Bool = false,
        remainingFreeStarts: Int = 0,
        currentPeriodEnd: Date? = nil,
        cancelAtPeriodEnd: Bool? = nil,
        onShowPaywall: (() -> Void)? = nil,
        onManageSubscription: (() -> Void)? = nil,
        pushStatus: NotificationPermissionStatus? = nil,
        pushRegistrationError: Error? = nil,
        onManagePushSettings: (() -> Void)? = nil,
        onShowPrivacySettings: (() -> Void)? = nil,
        notificationSettingsModel: NotificationSettingsModel? = nil
    ) {
        self.isPro = isPro
        self.remainingFreeStarts = remainingFreeStarts
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.onShowPaywall = onShowPaywall
        self.onManageSubscription = onManageSubscription
        self.pushStatus = pushStatus
        self.pushRegistrationError = pushRegistrationError
        self.onManagePushSettings = onManagePushSettings
        self.onShowPrivacySettings = onShowPrivacySettings
        self.notificationSettingsModel = notificationSettingsModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                subscriptionSection
                if pushStatus != nil {
                    pushSection
                }
                privacySection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // MARK: - Push notifications section

    @ViewBuilder
    private var pushSection: some View {
        if let status = pushStatus {
            Section("Push Notifications") {
                HStack {
                    Label("Status", systemImage: pushStatusIcon(status))
                        .foregroundStyle(Color.cfLabel)
                    Spacer()
                    Text(pushStatusLabel(status))
                        .font(.cfSubheadline)
                        .foregroundStyle(pushStatusColor(status))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Push notification status: \(pushStatusLabel(status))")

                if status == .denied {
                    Button(action: { onManagePushSettings?() }) {
                        Label("Enable in Settings", systemImage: "arrow.up.right")
                            .foregroundStyle(Color.cfAccent)
                    }
                    .accessibilityLabel("Open iOS Settings to enable push notifications")
                }

                if let error = pushRegistrationError {
                    HStack(spacing: .cfSpacing8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.orange)
                            .accessibilityHidden(true)
                        Text(error.localizedDescription)
                            .font(.cfFootnote)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Registration error: \(error.localizedDescription)")
                }

                if let notifModel = notificationSettingsModel {
                    NavigationLink {
                        NotificationSettingsView(model: notifModel)
                    } label: {
                        Label("Notification Preferences", systemImage: "bell.and.waves.left.and.right")
                            .foregroundStyle(Color.cfLabel)
                    }
                    .accessibilityLabel("Open notification preferences")
                    .accessibilityHint("Manage reminders, digests, and alert types")
                }
            }
        }
    }

    private func pushStatusLabel(_ status: NotificationPermissionStatus) -> String {
        switch status {
        case .authorized: return "On"
        case .provisional: return "Provisional"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        case .ephemeral: return "Ephemeral"
        }
    }

    private func pushStatusIcon(_ status: NotificationPermissionStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell"
        }
    }

    private func pushStatusColor(_ status: NotificationPermissionStatus) -> Color {
        switch status {
        case .authorized, .provisional, .ephemeral: return Color.cfAccent
        case .denied: return Color.orange
        case .notDetermined: return Color.cfSecondaryLabel
        }
    }

    // MARK: - Privacy section

    private var privacySection: some View {
        Section("Privacy") {
            Button {
                onShowPrivacySettings?()
            } label: {
                HStack {
                    Label("Privacy Settings", systemImage: "lock.shield")
                        .foregroundStyle(Color.cfLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy Settings")
            .accessibilityHint("Control what reading partners can see on your profile")
        }
    }

    // MARK: - Subscription section

    private var subscriptionSection: some View {
        Section("Subscription") {
            planRow

            if isPro {
                periodEndRow
                manageSubscriptionRow
            } else {
                if remainingFreeStarts > 0 {
                    freeStartsRow
                }
                upgradeRow
            }
        }
    }

    private var planRow: some View {
        HStack {
            Text("Plan")
                .foregroundStyle(Color.cfLabel)
            Spacer()
            Text(isPro ? "Pro" : "Free")
                .font(.cfSubheadline.weight(isPro ? .semibold : .regular))
                .foregroundStyle(isPro ? Color.cfAccent : Color.cfSecondaryLabel)
                .padding(.horizontal, .cfSpacing8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isPro ? Color.cfAccent.opacity(0.12) : Color.cfSecondaryFill))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subscription plan: \(isPro ? "Pro" : "Free")")
    }

    @ViewBuilder
    private var periodEndRow: some View {
        if let date = currentPeriodEnd {
            let isCancelling = cancelAtPeriodEnd == true
            HStack {
                Text(isCancelling ? "Cancels" : "Renews")
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(isCancelling ? Color.orange : Color.cfSecondaryLabel)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isCancelling
                    ? "Subscription cancels on \(date.formatted(date: .long, time: .omitted))"
                    : "Subscription renews on \(date.formatted(date: .long, time: .omitted))"
            )
        }
    }

    private var manageSubscriptionRow: some View {
        Button {
            onManageSubscription?()
        } label: {
            Label("Manage Subscription", systemImage: "creditcard")
                .foregroundStyle(Color.cfAccent)
        }
        .accessibilityLabel("Manage your subscription in the App Store")
    }

    private var freeStartsRow: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "books.vertical")
                .foregroundStyle(Color.cfSecondaryLabel)
            Text(remainingFreeStarts == 1
                 ? "1 free book start remaining"
                 : "\(remainingFreeStarts) free book starts remaining")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(remainingFreeStarts) free book \(remainingFreeStarts == 1 ? "start" : "starts") remaining"
        )
    }

    private var upgradeRow: some View {
        Button {
            onShowPaywall?()
        } label: {
            HStack {
                Label("Upgrade to ChapterFlow Pro", systemImage: "crown")
                    .foregroundStyle(Color.cfAccent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upgrade to ChapterFlow Pro")
        .accessibilityHint("Opens the subscription upgrade screen")
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Settings — Free user with starts") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 3
    )
}

#Preview("Settings — Free user, no starts") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 0
    )
}

#Preview("Settings — Pro, renewing") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false
    )
}

#Preview("Settings — Pro, cancelling") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 10 * 24 * 3600),
        cancelAtPeriodEnd: true
    )
}

#Preview("Settings — Dark mode, Pro") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false,
        pushStatus: NotificationPermissionStatus.authorized
    )
    .preferredColorScheme(.dark)
}

#Preview("Settings — Push denied") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 1,
        pushStatus: NotificationPermissionStatus.denied,
        onManagePushSettings: {}
    )
}

#Preview("Settings — Push not determined") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 0,
        pushStatus: NotificationPermissionStatus.notDetermined
    )
}

#Preview("Settings — With notification prefs link") {
    SettingsView(
        isPro: false,
        remainingFreeStarts: 1,
        pushStatus: NotificationPermissionStatus.authorized,
        notificationSettingsModel: NotificationSettingsModel(
            repository: FakeNotificationPreferencesRepository(),
            authorizer: PreviewNotificationAuthorizer()
        )
    )
}

#Preview("Settings — XXL text") {
    SettingsView(isPro: false, remainingFreeStarts: 2, pushStatus: NotificationPermissionStatus.authorized)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Settings — with privacy callback") {
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false,
        onShowPrivacySettings: { print("Open privacy settings") }
    )
}

#endif
