import Foundation
import Observation
import CoreKit

#if canImport(UIKit)
import UIKit
#endif

/// Privacy-safe registration failures suitable for user-facing status UI.
public enum APNSRegistrationError: Error, LocalizedError, Sendable, Equatable {
    case systemRegistrationFailed
    case backendRegistrationFailed
    case backendUnregistrationFailed

    public var errorDescription: String? {
        switch self {
        case .systemRegistrationFailed:
            return "Push notifications could not be enabled. Please try again."
        case .backendRegistrationFailed:
            return "Push notifications could not be connected. Please try again."
        case .backendUnregistrationFailed:
            return "Push notifications could not be disconnected. Please try again."
        }
    }
}

/// The privacy-safe result of transitioning APNs registration during sign-out.
public enum APNSSignOutTransition: Sendable, Equatable {
    case noRegisteredToken
    case unregistered
    case unregistrationFailed
}

/// Orchestrates APNs token registration for one authenticated session scope.
///
/// The caller supplies an opaque, privacy-safe storage namespace. Tokens from
/// legacy global storage are deliberately ignored so they cannot be attributed
/// to the current account.
@Observable
@MainActor
public final class APNSRegistrationManager {

    // MARK: - Observable state

    public private(set) var pushStatus: NotificationPermissionStatus = .notDetermined
    public private(set) var registrationError: Error?

    // MARK: - Private

    private let authorizer: any NotificationAuthorizerProtocol
    private let repository: any DeviceRegistrationRepository
    private let defaults: UserDefaults
    private let tokenDefaultsKey: String
    private let bridgeOwnerID = UUID()
    private let log = AppLog(category: .notifications)

    private var isStarted = false
    private var isPaused = false
    private var lifecycleGeneration = 0
    private var statusObserverTask: Task<Void, Never>?
    private var authorizationRefreshTask: Task<Void, Never>?
    private var tokenRegistrationTask: Task<Void, Never>?
    private var allowedPendingRegistrationGeneration: Int?

    // MARK: - Init

    public init(
        authorizer: any NotificationAuthorizerProtocol,
        repository: any DeviceRegistrationRepository,
        storageNamespace: String,
        defaults: UserDefaults = .standard
    ) {
        precondition(!storageNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.authorizer = authorizer
        self.repository = repository
        self.defaults = defaults
        self.tokenDefaultsKey = "com.chapterflow.apns.v2.\(storageNamespace).last-token"
    }

    // MARK: - Lifecycle

    /// Starts the registration flow once. Repeated calls are idempotent.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        isPaused = false
        activate()
    }

    /// Reversibly quiesces this session's APNs work and detaches its bridge.
    public func pause() {
        pause(cancelPendingRegistration: true)
    }

    private func pause(cancelPendingRegistration: Bool) {
        guard isStarted, !isPaused else { return }
        isPaused = true
        lifecycleGeneration &+= 1
        cancelTasks(cancelPendingRegistration: cancelPendingRegistration)
        APNSRegistrationBridge.shared.detach(ownerID: bridgeOwnerID)
    }

    /// Resumes the exact same session manager after a reversible pause.
    public func resume() {
        guard isStarted else {
            start()
            return
        }
        guard isPaused else { return }
        isPaused = false
        activate()
    }

    /// Permanently stops this scope and clears its in-memory presentation state.
    /// Persisted token state is retained unless backend unregistration succeeded.
    public func stopAndReset() {
        allowedPendingRegistrationGeneration = nil
        lifecycleGeneration &+= 1
        cancelTasks()
        APNSRegistrationBridge.shared.detach(ownerID: bridgeOwnerID)
        isStarted = false
        isPaused = false
        pushStatus = .notDetermined
        registrationError = nil
    }

    // MARK: - Sign-out / revocation

    /// Quiesces APNs and unregisters this account's scoped token.
    ///
    /// A failed backend acknowledgement leaves the token intact so the same
    /// account scope can resume or retry without falsely claiming success.
    @discardableResult
    public func handleSignOut() async -> APNSSignOutTransition {
        let pendingRegistration = tokenRegistrationTask
        allowedPendingRegistrationGeneration = lifecycleGeneration
        // Detach every producer immediately, but join an already accepted
        // registration instead of cancelling it. The backend may have committed
        // that request; once it acknowledges, handleTokenReceived persists the
        // candidate and this method can deterministically unregister it.
        pause(cancelPendingRegistration: false)
        await pendingRegistration?.value
        allowedPendingRegistrationGeneration = nil
        tokenRegistrationTask = nil
        guard let token = defaults.string(forKey: tokenDefaultsKey) else {
            return .noRegisteredToken
        }

        do {
            try await repository.unregister(apnsToken: token)
            defaults.removeObject(forKey: tokenDefaultsKey)
            log.info("APNs token unregistered on sign-out")
            return .unregistered
        } catch {
            log.error("APNs token unregistration failed on sign-out")
            registrationError = APNSRegistrationError.backendUnregistrationFailed
            return .unregistrationFailed
        }
    }

    // MARK: - Token receipt

    /// Processes a token delivered for the current session scope.
    /// The token is persisted only after backend acknowledgement.
    func handleTokenReceived(_ data: Data) async {
        await handleTokenReceived(data, generation: lifecycleGeneration)
    }

    func handleRegistrationFailed(_: Error) {
        log.error("APNs system registration failed")
        registrationError = APNSRegistrationError.systemRegistrationFailed
    }

    // MARK: - Test synchronization

    func waitForPendingOperations() async {
        let refreshTask = authorizationRefreshTask
        let registrationTask = tokenRegistrationTask
        await refreshTask?.value
        await registrationTask?.value
    }

    var storedToken: String? {
        defaults.string(forKey: tokenDefaultsKey)
    }

    var isPausedForTesting: Bool {
        isPaused
    }

    // MARK: - Private helpers

    private func activate() {
        let generation = lifecycleGeneration
        wireBridge()
        statusObserverTask = Task { [weak self] in
            await self?.observeAppForeground(generation: generation)
        }
        scheduleAuthorizationRefresh(generation: generation)
    }

    private func cancelTasks(cancelPendingRegistration: Bool = true) {
        statusObserverTask?.cancel()
        statusObserverTask = nil
        authorizationRefreshTask?.cancel()
        authorizationRefreshTask = nil
        if cancelPendingRegistration {
            tokenRegistrationTask?.cancel()
            tokenRegistrationTask = nil
        }
    }

    private func wireBridge() {
        APNSRegistrationBridge.shared.attach(
            ownerID: bridgeOwnerID,
            onTokenReceived: { [weak self] data in
                self?.scheduleTokenRegistration(data)
            },
            onRegistrationFailed: { [weak self] error in
                self?.handleRegistrationFailed(error)
            }
        )
    }

    private func scheduleAuthorizationRefresh(generation: Int) {
        authorizationRefreshTask?.cancel()
        authorizationRefreshTask = Task { [weak self] in
            await self?.refreshAndRegisterIfNeeded(generation: generation)
        }
    }

    private func scheduleTokenRegistration(_ data: Data) {
        guard isStarted, !isPaused else { return }
        tokenRegistrationTask?.cancel()
        let generation = lifecycleGeneration
        tokenRegistrationTask = Task { [weak self] in
            await self?.handleTokenReceived(data, generation: generation)
        }
    }

    private func handleTokenReceived(_ data: Data, generation: Int) async {
        guard isCurrent(generation), !Task.isCancelled else { return }
        let hex = data.apnsHex
        let previous = defaults.string(forKey: tokenDefaultsKey)

        guard hex != previous else {
            registrationError = nil
            log.info("APNs token unchanged — skipping registration")
            return
        }

        do {
            if let previous {
                try await repository.unregister(apnsToken: previous)
                guard isCurrent(generation), !Task.isCancelled else { return }
            }

            try await repository.register(apnsToken: hex)
            // Persist every acknowledged registration, even if this scope was
            // paused while the request was in flight. Sign-out waits for this
            // task and can then truthfully unregister the scoped token.
            guard isCurrent(generation)
                    || allowedPendingRegistrationGeneration == generation else { return }
            defaults.set(hex, forKey: tokenDefaultsKey)
            guard isCurrent(generation), !Task.isCancelled else { return }
            registrationError = nil
        } catch {
            guard isCurrent(generation), !Task.isCancelled else { return }
            log.error("APNs backend registration transition failed")
            registrationError = APNSRegistrationError.backendRegistrationFailed
        }
    }

    private func refreshAndRegisterIfNeeded(generation: Int) async {
        let current = await authorizer.currentStatus()
        guard isCurrent(generation), !Task.isCancelled else { return }
        pushStatus = current

        switch current {
        case .authorized, .provisional:
            triggerAPNSRegistration()
        case .denied:
            await unregisterForPermissionRevocation(generation: generation)
        case .notDetermined, .ephemeral:
            break
        }
    }

    private func unregisterForPermissionRevocation(generation: Int) async {
        guard let token = defaults.string(forKey: tokenDefaultsKey) else { return }
        do {
            try await repository.unregister(apnsToken: token)
            guard isCurrent(generation), !Task.isCancelled else { return }
            defaults.removeObject(forKey: tokenDefaultsKey)
        } catch {
            guard isCurrent(generation), !Task.isCancelled else { return }
            log.error("APNs token unregistration failed after permission revocation")
            registrationError = APNSRegistrationError.backendUnregistrationFailed
        }
    }

    private func observeAppForeground(generation: Int) async {
        #if canImport(UIKit)
        let notifications = NotificationCenter.default.notifications(
            named: UIApplication.didBecomeActiveNotification
        )
        for await _ in notifications {
            guard isCurrent(generation), !Task.isCancelled else { return }
            scheduleAuthorizationRefresh(generation: generation)
        }
        #endif
    }

    private func isCurrent(_ generation: Int) -> Bool {
        isStarted && !isPaused && lifecycleGeneration == generation
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
