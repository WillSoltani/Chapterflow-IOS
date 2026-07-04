import Foundation
import Observation
import CoreKit

#if canImport(UIKit)
import UIKit
#endif

/// Orchestrates APNs token registration with the ChapterFlow backend.
///
/// **Lifecycle:**
/// 1. Created and owned by `AppModel`.
/// 2. Call `start()` once after auth resolves to `.signedIn`.
/// 3. On sign-out call `handleSignOut()`.
///
/// **Token management:**
/// - De-duplicates by comparing the new token's hex to the last registered hex
///   stored in `UserDefaults` — re-registration only fires when the token changes.
/// - The stored token persists across launches so a fresh registration is NOT
///   issued on every cold start (only when the token actually rotates).
/// - Unregisters on sign-out and when the OS status transitions to `.denied`.
@Observable
@MainActor
public final class APNSRegistrationManager {

    // MARK: - Observable state

    /// The current OS push authorization status (refreshed on foreground).
    public private(set) var pushStatus: NotificationPermissionStatus = .notDetermined

    /// Non-fatal registration error surfaced in Settings (e.g. APNs unavailable on
    /// Simulator). Cleared on the next successful registration.
    public private(set) var registrationError: Error?

    // MARK: - Private

    private let authorizer: any NotificationAuthorizerProtocol
    private let repository: any DeviceRegistrationRepository
    private let defaults: UserDefaults
    private let log = AppLog(category: .notifications)

    private static let lastTokenKey = "com.chapterflow.apnsLastRegisteredToken"

    private var statusObserverTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        authorizer: any NotificationAuthorizerProtocol,
        repository: any DeviceRegistrationRepository,
        defaults: UserDefaults = .standard
    ) {
        self.authorizer = authorizer
        self.repository = repository
        self.defaults = defaults
    }

    // MARK: - Lifecycle

    /// Starts APNs registration flow.
    ///
    /// - Wires the `APNSRegistrationBridge` callbacks (must be called before
    ///   the app delegate can deliver tokens).
    /// - Refreshes the authorization status.
    /// - If already authorized/provisional, calls `registerForRemoteNotifications`.
    /// - Begins observing app-foreground notifications to detect Settings.app changes.
    public func start() {
        wireBridge()
        statusObserverTask = Task { await observeAppForeground() }
        Task { await refreshAndRegisterIfNeeded() }
    }

    // MARK: - Sign-out / revocation

    /// Unregisters the stored token from the backend and clears local state.
    /// Call from `AppModel` when the user signs out.
    public func handleSignOut() async {
        if let token = defaults.string(forKey: Self.lastTokenKey) {
            await repository.unregister(apnsToken: token)
            defaults.removeObject(forKey: Self.lastTokenKey)
            log.info("APNs token unregistered on sign-out")
        }
    }

    // MARK: - Token receipt

    /// Processes a device token received from APNs.
    /// De-duplicates: only calls the backend when the token hex changes.
    func handleTokenReceived(_ data: Data) async {
        registrationError = nil
        let hex = data.apnsHex
        let previous = defaults.string(forKey: Self.lastTokenKey)

        guard hex != previous else {
            log.info("APNs token unchanged — skipping registration")
            return
        }

        // Unregister the old token before registering the new one.
        if let old = previous {
            await repository.unregister(apnsToken: old)
        }

        await repository.register(apnsToken: hex)
        defaults.set(hex, forKey: Self.lastTokenKey)
    }

    func handleRegistrationFailed(_ error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription)")
        registrationError = error
    }

    // MARK: - Private helpers

    private func wireBridge() {
        APNSRegistrationBridge.shared.onTokenReceived = { [weak self] data in
            Task { await self?.handleTokenReceived(data) }
        }
        APNSRegistrationBridge.shared.onRegistrationFailed = { [weak self] error in
            self?.handleRegistrationFailed(error)
        }
    }

    private func refreshAndRegisterIfNeeded() async {
        let current = await authorizer.currentStatus()
        pushStatus = current

        switch current {
        case .authorized, .provisional:
            triggerAPNSRegistration()
        case .denied:
            // If the OS revoked permission, unregister from the backend.
            await handleSignOut()
        case .notDetermined, .ephemeral:
            break
        }
    }

    private func observeAppForeground() async {
        #if canImport(UIKit)
        let notifications = NotificationCenter.default.notifications(
            named: UIApplication.didBecomeActiveNotification
        )
        for await _ in notifications {
            await refreshAndRegisterIfNeeded()
        }
        #endif
    }

    private func triggerAPNSRegistration() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}

// MARK: - Data → APNs hex

extension Data {
    /// Converts a raw APNs device token `Data` to its canonical hex string.
    var apnsHex: String {
        map { String(format: "%02.2hhx", $0) }.joined()
    }
}
