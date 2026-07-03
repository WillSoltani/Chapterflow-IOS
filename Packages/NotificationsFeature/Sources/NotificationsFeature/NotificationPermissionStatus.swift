import UserNotifications

/// The OS-level notification authorization status, mapped from `UNAuthorizationStatus`.
public enum NotificationPermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    init(_ raw: UNAuthorizationStatus) {
        switch raw {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        #if !os(macOS)
        case .ephemeral: self = .ephemeral
        #endif
        @unknown default: self = .notDetermined
        }
    }
}
