import SwiftUI
import DesignSystem
import CoreKit
import Persistence
import NotificationsFeature
import SyncEngine

// MARK: - Legal URL constants (company website)

private enum LegalURL {
    static let privacy   = URL(string: "https://chapterflow.ca/legal/privacy")!
    static let terms     = URL(string: "https://chapterflow.ca/legal/terms")!
    static let refund    = URL(string: "https://chapterflow.ca/legal/refund")!
    static let dataRights = URL(string: "https://chapterflow.ca/legal/data-rights")!
}

// MARK: - SettingsView

/// The Settings tab.
///
/// Shows the user's current subscription plan, upgrade or manage-subscription
/// options, and general app preferences. Keeps subscription upgrade prompts
/// non-intrusive — they are informational rows, not modal banners.
///
/// All subscription state is injected from `AppFeature` via `EntitlementService`;
/// SettingsFeature itself has no StoreKit dependency.
public struct SettingsView: View {

    // MARK: Subscription / plan (passed from AppModel.entitlementService)

    let isPro: Bool
    let remainingFreeStarts: Int
    let currentPeriodEnd: Date?
    let cancelAtPeriodEnd: Bool?
    let onShowPaywall: (() -> Void)?
    let onManageSubscription: (() -> Void)?

    // MARK: Push / notification state (P9.2)

    let pushStatus: NotificationPermissionStatus?
    let pushRegistrationError: Error?
    let onManagePushSettings: (() -> Void)?

    // MARK: Privacy (P7.8)

    /// Called when the user taps "Privacy Settings" — navigate to
    /// ``PrivacySettingsView`` in your feature's navigation stack.
    let onShowPrivacySettings: (() -> Void)?

    // MARK: Notification preferences (P9.2)

    let notificationSettingsModel: NotificationSettingsModel?

    // MARK: Full settings model (P10.1)

    /// Set by `AppRootView` to enable the server-backed sections: reading
    /// preferences, downloads, export, and account lifecycle.
    let settingsModel: SettingsModel?

    // MARK: Sync status (P3.5)

    /// Live sync status from the outbox drain engine. When non-nil, a "Sync" section
    /// appears showing idle/syncing/error phase, pending count, and last-synced time.
    let syncStatus: SyncStatus?

    /// The user's email displayed in the Account section.
    let userEmail: String?

    /// Called to sign the user out (routes through `AppModel.signOut`).
    let onSignOut: (() async -> Void)?

    // MARK: What's New (P10.9)

    /// Drives the always-available "What's New" entry in the About section.
    @State private var whatsNewModel = WhatsNewModel()
    @State private var showWhatsNew = false

    // MARK: App version

    private var appVersion: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(ver) (\(build))"
    }

    // MARK: - Init

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
        notificationSettingsModel: NotificationSettingsModel? = nil,
        settingsModel: SettingsModel? = nil,
        syncStatus: SyncStatus? = nil,
        userEmail: String? = nil,
        onSignOut: (() async -> Void)? = nil
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
        self.settingsModel = settingsModel
        self.syncStatus = syncStatus
        self.userEmail = userEmail
        self.onSignOut = onSignOut
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                accountSection
                subscriptionSection
                readingSection
                if pushStatus != nil {
                    pushSection
                }
                appLockSection
                downloadsSection
                syncSection
                privacyLegalSection
                dataSection
                aboutSection
                dangerZoneSection
                signOutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .task { await settingsModel?.load() }
        .sheet(isPresented: $showWhatsNew) {
            if let release = whatsNewModel.displayRelease {
                WhatsNewView(release: release)
            }
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { settingsModel?.showShareSheet ?? false },
            set: { settingsModel?.showShareSheet = $0 }
        )) {
            if let data = settingsModel?.exportData {
                ShareSheet(items: [data])
            }
        }
        #endif
        .sheet(isPresented: Binding(
            get: { settingsModel?.showDeleteConfirm ?? false },
            set: { settingsModel?.showDeleteConfirm = $0 }
        )) {
            DeleteAccountSheet(
                isPresented: Binding(
                    get: { settingsModel?.showDeleteConfirm ?? false },
                    set: { settingsModel?.showDeleteConfirm = $0 }
                ),
                isLoading: settingsModel?.isDangerousOperationInProgress ?? false,
                onConfirm: { await settingsModel?.confirmDelete() }
            )
        }
        .alert("Deactivate Account?", isPresented: Binding(
            get: { settingsModel?.showDeactivateConfirm ?? false },
            set: { settingsModel?.showDeactivateConfirm = $0 }
        )) {
            Button("Deactivate", role: .destructive) {
                Task { await settingsModel?.confirmDeactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be paused. Sign in again to reactivate it.")
        }
    }

    // MARK: - Account section

    private var accountSection: some View {
        Section("Account") {
            if let email = userEmail, !email.isEmpty {
                LabeledContent("Email", value: email)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Account email: \(email)")
            }
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
        .accessibilityIdentifier("settings-upgrade-to-pro")
        .accessibilityLabel("Upgrade to ChapterFlow Pro")
        .accessibilityHint("Opens the subscription upgrade screen")
    }

    // MARK: - Reading preferences section

    @ViewBuilder
    private var readingSection: some View {
        if let model = settingsModel {
            Section("Reading") {
                Picker("Depth", selection: Binding(
                    get: { model.preferences.depthVariant },
                    set: { model.preferences.depthVariant = $0; model.readingPreferencesDidChange() }
                )) {
                    ForEach(DepthVariant.allCases, id: \.self) { v in
                        Text(v.rawValue.capitalized).tag(v)
                    }
                }
                .accessibilityLabel("Default reading depth")

                Picker("Tone", selection: Binding(
                    get: { model.preferences.readingTone },
                    set: { model.preferences.readingTone = $0; model.readingPreferencesDidChange() }
                )) {
                    ForEach(ReadingTone.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .accessibilityLabel("Teaching tone")

                Picker("Reader Theme", selection: Binding(
                    get: { model.preferences.readerTheme },
                    set: { model.preferences.readerTheme = $0 }
                )) {
                    ForEach(ReadingTheme.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .accessibilityLabel("Reader visual theme")

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    HStack {
                        Text("Font Scale")
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        Text(String(format: "%.0f%%", model.preferences.readerFontScale * 100))
                            .font(.cfCaption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.preferences.readerFontScale },
                            set: { model.preferences.readerFontScale = $0; model.readingPreferencesDidChange() }
                        ),
                        in: 0.8...1.8,
                        step: 0.05
                    )
                    .accessibilityLabel("Font scale: \(Int(model.preferences.readerFontScale * 100)) percent")
                }

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    HStack {
                        Text("Audio Speed")
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        Text(String(format: "%.1f×", model.preferences.audioSpeed))
                            .font(.cfCaption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.preferences.audioSpeed },
                            set: { model.preferences.audioSpeed = $0; model.readingPreferencesDidChange() }
                        ),
                        in: 0.5...3.0,
                        step: 0.25
                    )
                    .accessibilityLabel("Audio speed: \(String(format: "%.1f", model.preferences.audioSpeed)) times")
                }
            }
        }
    }

    // MARK: - App Lock section

    @ViewBuilder
    private var appLockSection: some View {
        if let model = settingsModel {
            Section("Security") {
                Toggle(isOn: Binding(
                    get: { model.appLockEnabled },
                    set: { model.appLockEnabled = $0 }
                )) {
                    Label("Face ID / Touch ID Lock", systemImage: "faceid")
                        .foregroundStyle(Color.cfLabel)
                }
                .accessibilityLabel("Require Face ID or Touch ID when opening the app")
            }
        }
    }

    // MARK: - Downloads section

    @ViewBuilder
    private var downloadsSection: some View {
        if let model = settingsModel {
            Section {
                // Navigate to the full DownloadsSettingsView
                NavigationLink {
                    DownloadsSettingsView(
                        downloadInfo: model.downloadInfoProvider,
                        preferences: model.preferences,
                        userId: model.userId
                    )
                } label: {
                    HStack {
                        Label("Downloads", systemImage: "arrow.down.circle")
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        if model.totalDownloadBytes > 0 {
                            Text(ByteCountFormatter.string(
                                fromByteCount: model.totalDownloadBytes,
                                countStyle: .file
                            ))
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                        }
                    }
                }
                .accessibilityLabel("Downloads settings")
            }
        }
    }

    // MARK: - Privacy & Legal section

    private var privacyLegalSection: some View {
        Section("Privacy & Legal") {
            Link(destination: LegalURL.privacy) {
                Label("Privacy Policy", systemImage: "lock.shield")
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Open Privacy Policy in browser")

            Link(destination: LegalURL.terms) {
                Label("Terms of Service", systemImage: "doc.text")
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Open Terms of Service in browser")

            Link(destination: LegalURL.refund) {
                Label("Refund Policy", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Open Refund Policy in browser")

            Link(destination: LegalURL.dataRights) {
                Label("Data Rights", systemImage: "person.badge.shield.checkmark")
                    .foregroundStyle(Color.cfLabel)
            }
            .accessibilityLabel("Open Data Rights page in browser")

            Button {
                onShowPrivacySettings?()
            } label: {
                HStack {
                    Label("Privacy Settings", systemImage: "hand.raised")
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

    // MARK: - Data section

    @ViewBuilder
    private var dataSection: some View {
        if let model = settingsModel {
            Section("Data") {
                Button {
                    Task { await model.requestExport() }
                } label: {
                    HStack {
                        Label("Export My Data", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        if model.isDangerousOperationInProgress {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
                .disabled(model.isDangerousOperationInProgress)
                .accessibilityLabel("Export my ChapterFlow data")
                .accessibilityHint("Downloads a JSON file with all your account data")
            }
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("App version: \(appVersion)")

            if whatsNewModel.displayRelease != nil {
                Button {
                    showWhatsNew = true
                } label: {
                    HStack {
                        Label("What's New", systemImage: "sparkles")
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What's New")
                .accessibilityHint("Shows the latest features in this release")
            }
        }
    }

    // MARK: - Danger zone section

    @ViewBuilder
    private var dangerZoneSection: some View {
        if let model = settingsModel {
            Section {
                Button(role: .destructive) {
                    model.showDeactivateConfirm = true
                } label: {
                    Label("Deactivate Account", systemImage: "pause.circle")
                }
                .disabled(model.isDangerousOperationInProgress)
                .accessibilityLabel("Deactivate account")
                .accessibilityHint("Temporarily pauses your account. You can reactivate by signing in.")

                Button(role: .destructive) {
                    model.showDeleteConfirm = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .disabled(model.isDangerousOperationInProgress)
                .accessibilityLabel("Delete account permanently")
                .accessibilityHint("Opens a confirmation screen before deleting")
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Deletion is permanent and immediately signs you out.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sign Out section

    @ViewBuilder
    private var signOutSection: some View {
        if onSignOut != nil {
            Section {
                Button(role: .destructive) {
                    Task { await onSignOut?() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .accessibilityLabel("Sign out of ChapterFlow")
            }
        }
    }
}
