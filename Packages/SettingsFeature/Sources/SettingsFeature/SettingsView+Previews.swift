import SwiftUI
import AuthKit
import CoreKit
import Persistence
import NotificationsFeature

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
            authorizer: PreviewNotificationAuthorizer(),
            pendingStore: KeyValueStore()
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

#Preview("Settings — Full (with model)") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.settings"))
    let model = SettingsModel(
        repository: FakeSettingsRepository(),
        preferences: prefs,
        onSignOut: {},
        accountContext: makeSettingsPreviewAccountContext()
    )
    SettingsView(
        isPro: true,
        currentPeriodEnd: Date(timeIntervalSinceNow: 28 * 24 * 3600),
        cancelAtPeriodEnd: false,
        pushStatus: .authorized,
        settingsModel: model,
        userEmail: "reader@example.com",
        onSignOut: {}
    )
}

#Preview("Settings — Full Dark") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.settings.dark"))
    let model = SettingsModel(
        repository: FakeSettingsRepository(),
        preferences: prefs,
        onSignOut: {},
        accountContext: makeSettingsPreviewAccountContext()
    )
    SettingsView(
        isPro: false,
        remainingFreeStarts: 2,
        pushStatus: .authorized,
        settingsModel: model,
        userEmail: "reader@example.com",
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Settings — Full XXL") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.settings.xxl"))
    let model = SettingsModel(
        repository: FakeSettingsRepository(),
        preferences: prefs,
        onSignOut: {},
        accountContext: makeSettingsPreviewAccountContext()
    )
    SettingsView(
        isPro: false,
        settingsModel: model,
        userEmail: "reader@example.com",
        onSignOut: {}
    )
    .dynamicTypeSize(.accessibility3)
}

func makeSettingsPreviewAccountContext() -> AccountContext {
    guard let identity = SessionIdentity(
        subject: "settings-preview-account",
        username: "preview-reader",
        email: "reader@example.test",
        source: .hermeticUITest
    ) else {
        preconditionFailure("Static preview identity must be valid")
    }

    let config = AppConfig(
        apiBaseURL: "https://api.chapterflow.test",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_ChapterFlowPreview",
        cognitoClientID: "ChapterFlowPreviewClient1234567890",
        cognitoDomain: "chapterflow-preview.auth.us-east-1.amazoncognito.com"
    )
    guard case let .valid(validatedConfig) = config.validate() else {
        preconditionFailure("Static preview configuration must be valid")
    }
    return AccountContext(identity: identity, config: validatedConfig)
}

#endif
