#if canImport(UIKit)
import UIKit
import UserNotifications
import NotificationsFeature
import CoreKit

/// The app's `UIApplicationDelegate`, wired in via `@UIApplicationDelegateAdaptor`
/// in `ChapterFlowApp`.
///
/// Responsibilities:
/// - Forward APNs token registration into `APNSRegistrationBridge`.
/// - Register push notification categories at launch (idempotent, safe before auth).
/// - Implement `UNUserNotificationCenterDelegate` to:
///     • Show alerts while the app is foregrounded.
///     • Route taps + inline actions to `PushRoutingBridge` → `AppModel`.
/// - Handle Home-screen Quick Action taps via `QuickActionBridge`.
public final class AppDelegate: NSObject, UIApplicationDelegate, @unchecked Sendable {

    private let log = AppLog(category: .notifications)

    // MARK: - Launch

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register categories before any notification can be delivered.
        PushCategoryRegistrar.registerCategories()
        // Set this delegate as the UNUserNotificationCenter delegate.
        UNUserNotificationCenter.current().delegate = self
        // Capture any quick action that launched the app cold.
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            QuickActionBridge.shared.pendingShortcutType = item.type
        }
        return true
    }

    // MARK: - Quick Actions

    /// Called when the user selects a Home-screen quick action while the app is running.
    /// Stores the shortcut type in `QuickActionBridge`; `AppModel` reads it on next
    /// scene activation and routes to the correct tab via the `DeepLinkParser`.
    public func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        QuickActionBridge.shared.pendingShortcutType = shortcutItem.type
        completionHandler(true)
    }

    // MARK: - APNs registration callbacks

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            APNSRegistrationBridge.shared.didReceiveToken(deviceToken)
        }
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        log.error("APNs registration failed: \(error.localizedDescription)")
        Task { @MainActor in
            APNSRegistrationBridge.shared.didFailToRegister(error)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is in the foreground.
    /// We always show the alert+badge+sound so the user sees the message.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    /// Called when the user taps a notification banner or an inline action button.
    /// Routes the response to `PushRoutingBridge` which calls the `AppModel`.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // didReceiveResponse is nonisolated — safe to call directly from the delegate.
        PushRoutingBridge.shared.didReceiveResponse(response)
        completionHandler()
    }
}
#endif
