import Foundation

/// The payload returned by `GET /book/config/ios` (backend prompt B4).
///
/// Drives force-update prompts, kill-switch feature flags, the StoreKit product
/// list, and a maintenance gate — all without shipping an app update.
public struct IOSConfig: Codable, Sendable, Equatable {
    /// The lowest app version still allowed to run (below this → hard update gate).
    public let minSupportedVersion: String
    /// The latest available version (used for soft "update available" nudges).
    public let latestVersion: String
    /// Remote feature-flag overrides, keyed by flag identifier.
    public let featureFlags: [String: Bool]
    /// StoreKit product identifiers to offer, so pricing can change server-side.
    public let storeKitProductIds: [String]
    /// When true, the app should show a maintenance screen.
    public let maintenanceMode: Bool
    /// An optional message-of-the-day to surface (e.g. on the home screen).
    public let messageOfTheDay: String?

    public init(
        minSupportedVersion: String,
        latestVersion: String,
        featureFlags: [String: Bool],
        storeKitProductIds: [String],
        maintenanceMode: Bool,
        messageOfTheDay: String?
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.latestVersion = latestVersion
        self.featureFlags = featureFlags
        self.storeKitProductIds = storeKitProductIds
        self.maintenanceMode = maintenanceMode
        self.messageOfTheDay = messageOfTheDay
    }
}
