import Foundation
import Observation
import CoreKit

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
    private let log = AppLog(category: .notifications)

    // MARK: - Init

    public init(
        repository: any NotificationPreferencesRepository,
        authorizer: any NotificationAuthorizerProtocol
    ) {
        self.repository = repository
        self.authorizer = authorizer
    }

    // MARK: - Lifecycle

    /// Call from `.task` in the settings view.
    public func onAppear() async {
        await refreshPermissionStatus()
        await loadIfNeeded()
    }

    /// Call when the app returns to the foreground (permissions may have changed in Settings).
    public func onForeground() async {
        await refreshPermissionStatus()
    }

    // MARK: - Load

    private func loadIfNeeded() async {
        guard preferences == nil, !isLoading else { return }
        isLoading = true
        do {
            preferences = try await repository.fetchPreferences()
        } catch {
            log.error("Failed to load notification preferences: \(error)")
            preferences = .default
        }
        isLoading = false
    }

    // MARK: - Save (optimistic)

    /// Applies a mutation to `preferences` immediately and persists it in the background.
    public func update(_ mutation: (inout NotificationPreferences) -> Void) {
        guard var current = preferences else { return }
        mutation(&current)
        preferences = current
        Task { await persist(current) }
    }

    private func persist(_ prefs: NotificationPreferences) async {
        do {
            try await repository.savePreferences(prefs)
            saveError = nil
        } catch {
            log.error("Failed to save notification preferences: \(error)")
            saveError = error
        }
    }

    // MARK: - Permission status

    private func refreshPermissionStatus() async {
        permissionStatus = await authorizer.currentStatus()
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
