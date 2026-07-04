import Foundation
import CoreKit
import Networking

// MARK: - Protocol

/// Reads and writes the user's server-side notification preferences.
///
/// Implementations must be `Sendable`; the live implementation is a struct.
public protocol NotificationPreferencesRepository: Sendable {
    /// Loads the current notification preferences from the server.
    /// Returns `NotificationPreferences.default` on network error so the UI
    /// always has something to display.
    func fetchPreferences() async throws -> NotificationPreferences

    /// Persists updated preferences to the server (`PATCH /book/me/settings`).
    func savePreferences(_ preferences: NotificationPreferences) async throws
}

// MARK: - Live implementation

public struct LiveNotificationPreferencesRepository: NotificationPreferencesRepository {
    private let apiClient: any APIClientProtocol
    private let log = AppLog(category: .notifications)

    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    public func fetchPreferences() async throws -> NotificationPreferences {
        let response: UserSettingsResponse = try await apiClient.send(Endpoints.getSettings())
        return response.notifications ?? .default
    }

    public func savePreferences(_ preferences: NotificationPreferences) async throws {
        let body = NotificationSettingsUpdate(from: preferences)
        let endpoint = try Endpoints.patchNotificationSettings(body)
        // The server returns the updated settings; we don't need to re-parse.
        let _: UserSettingsResponse = try await apiClient.send(endpoint)
        log.info("Notification preferences saved")
    }
}

// MARK: - Fake (for tests and previews)

public final class FakeNotificationPreferencesRepository: NotificationPreferencesRepository, @unchecked Sendable {
    public var stubbedPreferences: NotificationPreferences
    public private(set) var savedPreferences: [NotificationPreferences] = []
    public var shouldThrow: Bool = false

    public init(preferences: NotificationPreferences = .default) {
        self.stubbedPreferences = preferences
    }

    public func fetchPreferences() async throws -> NotificationPreferences {
        if shouldThrow { throw AppError.offline }
        return stubbedPreferences
    }

    public func savePreferences(_ preferences: NotificationPreferences) async throws {
        if shouldThrow { throw AppError.offline }
        savedPreferences.append(preferences)
        stubbedPreferences = preferences
    }
}
