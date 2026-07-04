import Foundation

/// A `@MainActor` singleton that bridges `UIApplicationDelegate` APNs callbacks
/// (which live in the app target) into the `APNSRegistrationManager` (which
/// lives inside `NotificationsFeature`).
///
/// **Usage:**
/// 1. In `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`,
///    call `APNSRegistrationBridge.shared.didReceiveToken(_:)`.
/// 2. In `APNSRegistrationManager.start()`, set the two callbacks on `.shared`.
///
/// The singleton is safe because APNs token delivery is always serialised on the
/// main queue by iOS, and both sides pin to `@MainActor`.
@MainActor
public final class APNSRegistrationBridge {

    public static let shared = APNSRegistrationBridge()
    private init() {}

    // Callbacks registered by APNSRegistrationManager.
    // nonisolated(unsafe) lets the closures be stored as mutable state on a
    // @MainActor type; callers must only write/read from the main actor.
    nonisolated(unsafe) var onTokenReceived: (@MainActor (Data) -> Void)?
    nonisolated(unsafe) var onRegistrationFailed: (@MainActor (Error) -> Void)?

    /// Called by the app target's `AppDelegate` when APNs delivers a device token.
    public func didReceiveToken(_ data: Data) {
        onTokenReceived?(data)
    }

    /// Called by the app target's `AppDelegate` when APNs registration fails.
    public func didFailToRegister(_ error: Error) {
        onRegistrationFailed?(error)
    }
}
