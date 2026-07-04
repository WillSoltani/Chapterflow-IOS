#if DEBUG
import Foundation

/// A canned `NotificationAuthorizerProtocol` for SwiftUI previews only.
/// Unit tests define their own `MockNotificationAuthorizer` in the test target.
public final class PreviewNotificationAuthorizer: NotificationAuthorizerProtocol, @unchecked Sendable {
    private let _status: NotificationPermissionStatus

    public init(status: NotificationPermissionStatus = .authorized) {
        self._status = status
    }

    public func currentStatus() async -> NotificationPermissionStatus { _status }

    public func requestAuthorization() async -> NotificationAuthorizationOutcome {
        _status == .authorized ? .granted : .denied
    }

    public func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome {
        .provisional
    }
}
#endif
