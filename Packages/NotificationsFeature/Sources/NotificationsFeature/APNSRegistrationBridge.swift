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

    private var ownerID: UUID?
    private var onTokenReceived: (@MainActor (Data) -> Void)?
    private var onRegistrationFailed: (@MainActor (Error) -> Void)?

    /// Attaches one session-owned registration manager. A newer owner safely
    /// supersedes an older one; the old owner cannot later detach the new one.
    func attach(
        ownerID: UUID,
        onTokenReceived: @escaping @MainActor (Data) -> Void,
        onRegistrationFailed: @escaping @MainActor (Error) -> Void
    ) {
        self.ownerID = ownerID
        self.onTokenReceived = onTokenReceived
        self.onRegistrationFailed = onRegistrationFailed
    }

    /// Detaches callbacks only when the caller still owns the bridge.
    func detach(ownerID: UUID) {
        guard self.ownerID == ownerID else { return }
        self.ownerID = nil
        onTokenReceived = nil
        onRegistrationFailed = nil
    }

    /// Called by the app target's `AppDelegate` when APNs delivers a device token.
    public func didReceiveToken(_ data: Data) {
        onTokenReceived?(data)
    }

    /// Called by the app target's `AppDelegate` when APNs registration fails.
    public func didFailToRegister(_ error: Error) {
        onRegistrationFailed?(error)
    }
}
