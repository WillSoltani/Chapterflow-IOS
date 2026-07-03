import Foundation

/// The outcome of a notification authorization request.
public enum NotificationAuthorizationOutcome: Sendable, Equatable {
    /// User was shown the OS prompt and tapped Allow.
    case granted
    /// User was shown the OS prompt and tapped Don't Allow, or the OS blocked it.
    case denied
    /// Provisional authorization was granted (silent, Notification Center only).
    case provisional
}

/// Testable interface over UNUserNotificationCenter authorization.
///
/// Both `NotificationPrimingCoordinator` (priming) and the future P9.1 APNs
/// registration call this — never call `UNUserNotificationCenter` directly for
/// permission decisions.
public protocol NotificationAuthorizerProtocol: Sendable {
    func currentStatus() async -> NotificationPermissionStatus
    func requestAuthorization() async -> NotificationAuthorizationOutcome
    func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome
}
