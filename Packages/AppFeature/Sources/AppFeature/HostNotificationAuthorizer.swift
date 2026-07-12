#if !os(iOS)
import NotificationsFeature

/// SwiftPM host builds have no application bundle, so
/// `UNUserNotificationCenter.current()` is unavailable. The iOS app always uses
/// the real authorizer; this conservative adapter keeps host-only logic tests
/// from touching an unsupported OS singleton.
struct HostNotificationAuthorizer: NotificationAuthorizerProtocol, Sendable {
    func currentStatus() async -> NotificationPermissionStatus { .notDetermined }
    func requestAuthorization() async -> NotificationAuthorizationOutcome { .denied }
    func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome { .denied }
}
#endif
