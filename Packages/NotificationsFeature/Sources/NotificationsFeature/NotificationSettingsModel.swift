import Foundation
import Observation
import CoreKit
import Persistence

#if canImport(UIKit)
import UIKit
#endif

/// Drives the Notification Settings screen.
///
/// - Loads server preferences via `NotificationPreferencesRepository`.
/// - Reflects live OS permission status (refreshed on appear + foreground).
/// - Writes changes optimistically: UI updates instantly, server call fires in
///   the background; failures are surfaced via `saveError`.
@Observable
@MainActor
public final class NotificationSettingsModel {

    // MARK: - Observable state

    /// Current notification preferences, `nil` while the initial load is in-flight.
    public private(set) var preferences: NotificationPreferences?

    /// Whether the initial load is running.
    public private(set) var isLoading: Bool = false

    /// Non-nil when the last save failed. Cleared on the next successful save.
    public private(set) var saveError: Error?

    /// The current OS authorization status (updated on appear and foreground resume).
    public private(set) var permissionStatus: NotificationPermissionStatus = .notDetermined

    // MARK: - Dependencies

    private let repository: any NotificationPreferencesRepository
    private let authorizer: any NotificationAuthorizerProtocol
    private let pendingStore: KeyValueStore
    private let log = AppLog(category: .notifications)
    private var lifecycleGeneration = 0
    private var saveTask: Task<Void, Never>?
    private var requiresRecovery = false

    static let pendingPreferencesKey = "notifications.pending-preferences"

    // MARK: - Init

    public init(
        repository: any NotificationPreferencesRepository,
        authorizer: any NotificationAuthorizerProtocol,
        pendingStore: KeyValueStore
    ) {
        self.repository = repository
        self.authorizer = authorizer
        self.pendingStore = pendingStore
    }

    // MARK: - Lifecycle

    /// Call from `.task` in the settings view.
    public func onAppear() async {
        let generation = lifecycleGeneration
        await refreshPermissionStatus(generation: generation)
        guard lifecycleGeneration == generation, !Task.isCancelled else { return }
        await loadIfNeeded(generation: generation)
    }

    /// Call when the app returns to the foreground (permissions may have changed in Settings).
    public func onForeground() async {
        await refreshPermissionStatus(generation: lifecycleGeneration)
    }

    // MARK: - Load

    private func loadIfNeeded(generation: Int) async {
        guard lifecycleGeneration == generation,
              !Task.isCancelled,
              preferences == nil,
              !isLoading else { return }
        isLoading = true
        defer {
            if lifecycleGeneration == generation {
                isLoading = false
            }
        }

        if let pending = pendingPreferences() {
            preferences = pending
            requiresRecovery = true
            saveError = PendingPreferencesRecoveryError()
            return
        }

        do {
            let fetched = try await repository.fetchPreferences()
            guard lifecycleGeneration == generation, !Task.isCancelled else { return }
            preferences = fetched
        } catch {
            guard lifecycleGeneration == generation, !Task.isCancelled else { return }
            log.error("Failed to load notification preferences")
            preferences = .default
        }
    }

    // MARK: - Save (optimistic)

    /// Applies a mutation to `preferences` immediately and persists it in the background.
    public func update(_ mutation: (inout NotificationPreferences) -> Void) {
        guard var current = preferences else { return }
        mutation(&current)
        do {
            try pendingStore.set(current, forKey: Self.pendingPreferencesKey)
        } catch {
            log.error("Failed to retain pending notification preferences")
            saveError = error
            return
        }
        preferences = current
        guard !requiresRecovery else {
            saveError = PendingPreferencesRecoveryError()
            return
        }
        startSaveWorkerIfNeeded(generation: lifecycleGeneration)
    }

    private func startSaveWorkerIfNeeded(generation: Int) {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            await self?.drainPendingPreferences(generation: generation)
        }
    }

    /// Delivers one snapshot at a time. If an update arrives while a request is
    /// in flight, the worker waits for that request to finish and then sends the
    /// newest durable snapshot. This prevents an older server write from racing
    /// and overwriting a newer acknowledged value.
    private func drainPendingPreferences(generation: Int) async {
        defer {
            if lifecycleGeneration == generation {
                saveTask = nil
            }
        }

        while lifecycleGeneration == generation,
              !Task.isCancelled,
              let pending = pendingPreferences() {
            do {
                try await repository.savePreferences(pending)
            } catch {
                guard lifecycleGeneration == generation, !Task.isCancelled else { return }
                log.error("Failed to save notification preferences")
                requiresRecovery = true
                saveError = error
                return
            }

            guard lifecycleGeneration == generation, !Task.isCancelled else { return }
            clearPendingPreferences(ifMatching: pending)
            saveError = nil
        }
    }

    /// Cancels local transport and clears account-private presentation state.
    /// Because cancellation cannot prove an accepted server write stopped, the
    /// latest account-owned pending value remains quarantined in this account's
    /// store instead of being automatically replayed by a later scope.
    public func cancelAndReset() async {
        lifecycleGeneration &+= 1
        let task = saveTask
        task?.cancel()
        preferences = nil
        isLoading = false
        saveError = nil
        permissionStatus = .notDetermined
        await task?.value
        saveTask = nil
        requiresRecovery = false
    }

    func waitForPendingSave() async {
        let task = saveTask
        await task?.value
    }

    private func pendingPreferences() -> NotificationPreferences? {
        pendingStore.value(NotificationPreferences.self, forKey: Self.pendingPreferencesKey)
    }

    private func clearPendingPreferences(ifMatching saved: NotificationPreferences) {
        guard pendingPreferences() == saved else { return }
        pendingStore.removeValue(forKey: Self.pendingPreferencesKey)
    }

    // MARK: - Permission status

    private func refreshPermissionStatus(generation: Int) async {
        let status = await authorizer.currentStatus()
        guard lifecycleGeneration == generation, !Task.isCancelled else { return }
        permissionStatus = status
    }

    // MARK: - OS Settings deep link

    /// Opens the iOS Settings app to the app's notification page.
    public func openSystemNotificationSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: "app-settings:") else { return }
        Task {
            await UIApplication.shared.open(url)
        }
        #endif
    }
}

private struct PendingPreferencesRecoveryError: LocalizedError {
    var errorDescription: String? {
        "Notification preference changes are retained locally and require recovery before syncing."
    }
}
