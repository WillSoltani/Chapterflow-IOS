import Foundation
import UserNotifications
import CoreKit

/// Centralized entry point for notification authorization.
///
/// This actor is the single place that calls `UNUserNotificationCenter` for
/// permission. P9.1 (APNs token registration) and P9.3 (local reminder scheduling)
/// both call the same instance — priming decides *when*, this decides *how*.
public actor NotificationAuthorizer: NotificationAuthorizerProtocol {
    private let analytics: any AnalyticsClient
    private let log = AppLog(category: .notifications)

    public init(analytics: any AnalyticsClient) {
        self.analytics = analytics
    }

    // MARK: - NotificationAuthorizerProtocol

    /// Reads the current OS authorization status without prompting the user.
    public func currentStatus() async -> NotificationPermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermissionStatus(settings.authorizationStatus)
    }

    /// Requests full (alert + badge + sound) authorization.
    ///
    /// Only call after showing the priming screen; the OS prompt will appear
    /// immediately after this returns. Tracks the outcome via analytics.
    public func requestAuthorization() async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            let outcome: NotificationAuthorizationOutcome = granted ? .granted : .denied
            analytics.track(.custom(
                name: granted ? "notification_os_granted" : "notification_os_denied",
                properties: [:]
            ))
            log.info("OS authorization outcome: \(granted ? "granted" : "denied")")
            return outcome
        } catch {
            log.error("requestAuthorization failed: \(error.localizedDescription)")
            analytics.track(.custom(name: "notification_os_denied",
                                    properties: ["reason": "request_error"]))
            return .denied
        }
    }

    /// Requests provisional authorization (Notification Center only — no OS alert).
    ///
    /// Safe to call without priming; provisional notifications are delivered
    /// silently. Upgrades to full authorization after priming is accepted.
    public func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound, .provisional])
            let outcome: NotificationAuthorizationOutcome = granted ? .provisional : .denied
            analytics.track(.custom(
                name: granted ? "notification_provisional_granted" : "notification_os_denied",
                properties: [:]
            ))
            log.info("Provisional authorization outcome: \(granted ? "provisional" : "denied")")
            return outcome
        } catch {
            log.error("requestProvisionalAuthorization failed: \(error.localizedDescription)")
            return .denied
        }
    }
}
