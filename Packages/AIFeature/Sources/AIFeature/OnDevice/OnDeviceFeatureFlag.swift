import Foundation

/// A lightweight feature flag that gates all on-device AI entry points.
///
/// Defaults to `true` (enabled) when the key has never been written so
/// the feature is "on" after the OS update on eligible devices. Set
/// `isEnabled = false` (e.g. from Settings) to hide all entry points.
///
/// Separate from `SystemLanguageModel.Availability` — the flag lets product
/// decisions override the hardware gate independently of OS availability.
public struct OnDeviceFeatureFlag: Sendable {

    // MARK: - State

    public let isEnabled: Bool

    // MARK: - Init

    /// Production init — reads from the supplied `UserDefaults` suite.
    /// Defaults to the shared app-group store, falling back to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        let stored = defaults.object(forKey: Keys.onDeviceAIEnabled)
        // nil means never explicitly written → default ON
        self.isEnabled = stored == nil ? true : defaults.bool(forKey: Keys.onDeviceAIEnabled)
    }

    /// Direct init for tests and previews.
    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    // MARK: - Mutation

    /// Writes the flag to the given store (used by a Settings toggle).
    public func save(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Keys.onDeviceAIEnabled)
    }

    // MARK: - Constants

    private enum Keys {
        static let onDeviceAIEnabled = "cf.onDeviceAI.enabled"
    }
}
