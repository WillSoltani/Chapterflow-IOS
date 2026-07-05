import Foundation
import CoreKit
import Models
import Networking
import Persistence

// MARK: - Models

/// Reading preferences synced with `GET /book/me/settings`.
///
/// All fields are optional so absent server keys fall back to the local
/// `AppPreferences` value without crashing (RF2 forward compatibility).
public struct UserReadingSettings: Codable, Sendable, Equatable {
    public var defaultDepth: String?
    public var readingTone: String?
    public var fontScale: Double?
    public var audioSpeed: Double?

    public init(
        defaultDepth: String? = nil,
        readingTone: String? = nil,
        fontScale: Double? = nil,
        audioSpeed: Double? = nil
    ) {
        self.defaultDepth = defaultDepth
        self.readingTone = readingTone
        self.fontScale = fontScale
        self.audioSpeed = audioSpeed
    }
}

/// Envelope for `GET /book/me/settings` — captures only the reading sub-keys.
/// Additional server fields are ignored (RF2 extra-field tolerance).
struct ReadingSettingsResponse: Decodable, Sendable {
    let settings: UserReadingSettings?

    private enum CodingKeys: String, CodingKey {
        case settings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(UserReadingSettings.self, forKey: .settings)
    }
}

/// Patch body for reading preferences sent to `PATCH /book/me/settings`.
struct ReadingSettingsPatch: Encodable, Sendable {
    struct SettingsBlock: Encodable, Sendable {
        let defaultDepth: String?
        let readingTone: String?
        let fontScale: Double?
        let audioSpeed: Double?
    }
    let settings: SettingsBlock
}

// MARK: - Protocol

/// Data contract for settings-related API operations.
public protocol SettingsRepository: Sendable {
    /// Fetches the user's server-side reading preferences.
    func getReadingSettings() async throws -> UserReadingSettings?
    /// Persists reading preferences to the server.
    func patchReadingSettings(_ patch: UserReadingSettings) async throws
    /// Downloads the user's full data export as raw bytes (JSON).
    func exportData() async throws -> Data
    /// Deactivates the account (reversible — sign in to reactivate).
    func deactivateAccount() async throws
    /// Permanently deletes the account (server revokes Apple token via B8).
    func deleteAccount() async throws
}

// MARK: - Live implementation

public struct LiveSettingsRepository: SettingsRepository {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func getReadingSettings() async throws -> UserReadingSettings? {
        let response: ReadingSettingsResponse = try await client.send(Endpoints.getSettings())
        return response.settings
    }

    public func patchReadingSettings(_ patch: UserReadingSettings) async throws {
        let body = ReadingSettingsPatch(
            settings: .init(
                defaultDepth: patch.defaultDepth,
                readingTone: patch.readingTone,
                fontScale: patch.fontScale,
                audioSpeed: patch.audioSpeed
            )
        )
        let endpoint = try Endpoints.updateSettings(body)
        // Server returns the updated settings; we don't need to re-parse here.
        let _: ReadingSettingsResponse = try await client.send(endpoint)
    }

    public func exportData() async throws -> Data {
        try await client.sendData(Endpoints.getExport())
    }

    public func deactivateAccount() async throws {
        struct Empty: Decodable, Sendable {}
        let endpoint = try Endpoints.deactivateAccount()
        let _: Empty = try await client.send(endpoint)
    }

    public func deleteAccount() async throws {
        struct Empty: Decodable, Sendable {}
        let endpoint = try Endpoints.deleteAccount()
        let _: Empty = try await client.send(endpoint)
    }
}

// MARK: - Fake implementation (tests & previews)

public final class FakeSettingsRepository: SettingsRepository, @unchecked Sendable {
    public var stubbedSettings: UserReadingSettings?
    public var stubbedExportData: Data
    public var shouldFail: Bool
    public private(set) var patchedSettings: UserReadingSettings?
    public private(set) var deactivateCalled = false
    public private(set) var deleteCalled = false

    public init(
        settings: UserReadingSettings? = UserReadingSettings(
            defaultDepth: "medium",
            readingTone: "direct",
            fontScale: 1.0,
            audioSpeed: 1.0
        ),
        exportData: Data = Data("{\"userId\":\"preview\",\"books\":[]}".utf8),
        shouldFail: Bool = false
    ) {
        self.stubbedSettings = settings
        self.stubbedExportData = exportData
        self.shouldFail = shouldFail
    }

    public func getReadingSettings() async throws -> UserReadingSettings? {
        if shouldFail { throw AppError.offline }
        return stubbedSettings
    }

    public func patchReadingSettings(_ patch: UserReadingSettings) async throws {
        if shouldFail { throw AppError.offline }
        patchedSettings = patch
    }

    public func exportData() async throws -> Data {
        if shouldFail { throw AppError.offline }
        return stubbedExportData
    }

    public func deactivateAccount() async throws {
        if shouldFail { throw AppError.offline }
        deactivateCalled = true
    }

    public func deleteAccount() async throws {
        if shouldFail { throw AppError.offline }
        deleteCalled = true
    }
}
