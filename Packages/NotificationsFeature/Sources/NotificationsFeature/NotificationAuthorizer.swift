import Foundation
import Observation
import UserNotifications
import CoreKit

/// The single point of contact for `UNUserNotificationCenter` authorization.
///
/// **Rules (per docs/ios/PUSH-CONTRACT.md):**
/// - Never call `UNUserNotificationCenter.requestAuthorization` directly —
///   always go through this type.
/// - APNs token registration may only proceed once `status` is `.authorized`
///   or `.provisional`.
@Observable
@MainActor
public final class NotificationAuthorizer {

    // MARK: - Observable state

    /// The current OS-reported authorization status (as `UNAuthorizationStatus`).
    /// Refreshed on `refresh()`.
    public private(set) var status: UNAuthorizationStatus = .notDetermined

    // MARK: - Dependencies

    let center: UNUserNotificationCenter
    let analytics: (any AnalyticsClient)?

    // MARK: - Init

    public init(
        center: UNUserNotificationCenter = .current(),
        analytics: (any AnalyticsClient)? = nil
    ) {
        self.center = center
        self.analytics = analytics
    }

    // MARK: - Status refresh

    /// Re-reads the OS status and updates the published `status` property.
    /// Call on app foreground to detect Settings.app changes.
    public func refresh() async {
        let settings = await center.notificationSettings()
        status = settings.authorizationStatus
    }
}

// MARK: - NotificationAuthorizerProtocol conformance

extension NotificationAuthorizer: NotificationAuthorizerProtocol {

    /// Returns the current status as `NotificationPermissionStatus`, also refreshing
    /// the observable `status` property.
    public func currentStatus() async -> NotificationPermissionStatus {
        await refresh()
        return NotificationPermissionStatus(status)
    }

    /// Requests full alert+badge+sound authorization from the OS.
    /// Never throws — catches any UNUserNotificationCenter error and treats it as denied.
    @discardableResult
    public func requestAuthorization() async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refresh()
            analytics?.track(granted ? .notificationOSGranted : .notificationOSDenied)
            return granted ? .granted : .denied
        } catch {
            await refresh()
            analytics?.track(.notificationOSDenied)
            return .denied
        }
    }

    /// Requests provisional authorization (silent delivery, no OS prompt).
    @discardableResult
    public func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            await refresh()
            if granted { analytics?.track(.notificationProvisionalGranted) }
            return granted ? .provisional : .denied
        } catch {
            await refresh()
            return .denied
        }
    }
}
