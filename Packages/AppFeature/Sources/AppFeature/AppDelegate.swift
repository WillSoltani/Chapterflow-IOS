#if canImport(UIKit)
import UIKit
import NotificationsFeature
import CoreKit

/// The app's `UIApplicationDelegate`, wired in via `@UIApplicationDelegateAdaptor`
/// in `ChapterFlowApp`.
///
/// Its only responsibility is to forward APNs registration callbacks into
/// `APNSRegistrationBridge` so `APNSRegistrationManager` (in `NotificationsFeature`)
/// can act on them without depending on the app target.
public final class AppDelegate: NSObject, UIApplicationDelegate, @unchecked Sendable {

    private let log = AppLog(category: .notifications)

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
#endif
