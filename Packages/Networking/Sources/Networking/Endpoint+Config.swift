import Foundation

// MARK: - Mobile config endpoint (B4)

extension Endpoints {
    /// `GET /book/config/ios` → ``IOSAppConfig``.
    ///
    /// A public, cacheable endpoint that drives client-side force-update prompts,
    /// a maintenance kill-switch, feature flags, and the StoreKit product ids.
    /// Public — never requires auth — so the app can consult it before (or without)
    /// a signed-in session and enforce a hard gate even on the sign-in screen.
    public static func getIOSConfig() -> Endpoint {
        Endpoint(method: .get, path: "/book/config/ios", requiresAuth: false)
    }
}

// MARK: - Response model

/// The mobile configuration payload served by `GET /book/config/ios` (B4).
///
/// Server-evolution contract (RF2): decoding is **totally tolerant**. Every field
/// is optional with a safe default and is read with `try?`, so a missing key, an
/// extra key, a `null`, or even a wrong JSON type for any single field can never
/// throw or crash a view. A completely unparseable body decodes to an all-defaults
/// value (equivalent to "no config"), which the gating logic treats as fail-open.
///
/// It is `Codable` so the last-good value can be cached to `UserDefaults` for
/// offline use.
public struct IOSAppConfig: Codable, Sendable, Equatable {
    /// The lowest app version the backend still supports. A running build below
    /// this triggers the hard "update required" gate. `nil` disables the gate.
    public let minSupportedVersion: String?
    /// The newest version available on the App Store. A running build below this
    /// (but at/above `minSupportedVersion`) triggers the dismissible soft nudge.
    /// `nil` disables the nudge.
    public let latestVersion: String?
    /// Server-driven kill-switch feature flags. Absent → empty (all off).
    public let featureFlags: [String: Bool]
    /// StoreKit product ids the paywall should offer. Absent → empty.
    public let storeKitProductIds: [String]
    /// When `true`, the backend is down for maintenance; the app shows the
    /// downtime screen. Absent → `false`.
    public let maintenanceMode: Bool
    /// Optional message shown on the update / maintenance screens (also usable as
    /// a general message-of-the-day).
    public let messageOfTheDay: String?
    /// Optional direct App Store product URL for the update button. When absent the
    /// client falls back to a built-in App Store link.
    public let appStoreURL: String?

    public init(
        minSupportedVersion: String? = nil,
        latestVersion: String? = nil,
        featureFlags: [String: Bool] = [:],
        storeKitProductIds: [String] = [],
        maintenanceMode: Bool = false,
        messageOfTheDay: String? = nil,
        appStoreURL: String? = nil
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.latestVersion = latestVersion
        self.featureFlags = featureFlags
        self.storeKitProductIds = storeKitProductIds
        self.maintenanceMode = maintenanceMode
        self.messageOfTheDay = messageOfTheDay
        self.appStoreURL = appStoreURL
    }

    private enum CodingKeys: String, CodingKey {
        case minSupportedVersion
        case latestVersion
        case featureFlags
        case storeKitProductIds
        case maintenanceMode
        case messageOfTheDay
        case appStoreURL
    }

    /// Fully tolerant decode: an unparseable container yields all-defaults; a bad
    /// value for any single field falls back to that field's default. This is the
    /// load-bearing fail-open guarantee — the config can never crash or hard-lock.
    public init(from decoder: any Decoder) throws {
        // An unparseable container leaves every field at its default (all-defaults
        // == "no config", which the gating logic treats as fail-open).
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            guard let container else { return nil }
            return (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        self.minSupportedVersion = string(.minSupportedVersion)
        self.latestVersion = string(.latestVersion)
        self.featureFlags = container.flatMap {
            (try? $0.decodeIfPresent([String: Bool].self, forKey: .featureFlags)) ?? nil
        } ?? [:]
        self.storeKitProductIds = container.flatMap {
            (try? $0.decodeIfPresent([String].self, forKey: .storeKitProductIds)) ?? nil
        } ?? []
        self.maintenanceMode = container.flatMap {
            (try? $0.decodeIfPresent(Bool.self, forKey: .maintenanceMode)) ?? nil
        } ?? false
        self.messageOfTheDay = string(.messageOfTheDay)
        self.appStoreURL = string(.appStoreURL)
    }
}
