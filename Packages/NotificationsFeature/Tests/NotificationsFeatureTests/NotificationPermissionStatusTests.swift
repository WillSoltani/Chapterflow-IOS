import Testing
import UserNotifications
@testable import NotificationsFeature

@Suite("NotificationPermissionStatus")
struct NotificationPermissionStatusTests {

    @Test("maps .notDetermined")
    func mapsNotDetermined() {
        #expect(NotificationPermissionStatus(.notDetermined) == .notDetermined)
    }

    @Test("maps .denied")
    func mapsDenied() {
        #expect(NotificationPermissionStatus(.denied) == .denied)
    }

    @Test("maps .authorized")
    func mapsAuthorized() {
        #expect(NotificationPermissionStatus(.authorized) == .authorized)
    }

    @Test("maps .provisional")
    func mapsProvisional() {
        #expect(NotificationPermissionStatus(.provisional) == .provisional)
    }

    // .ephemeral is iOS-only (unavailable on macOS)
    #if !os(macOS)
    @Test("maps .ephemeral")
    func mapsEphemeral() {
        #expect(NotificationPermissionStatus(.ephemeral) == .ephemeral)
    }
    #endif
}
