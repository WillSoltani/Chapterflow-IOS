import Foundation
import Observation

/// Observable feature-flag provider seeded with safe local defaults.
///
/// Flags resolve immediately from built-in defaults, so features behave sanely
/// offline and before the first `GET /book/config/ios` fetch. Once a remote
/// `IOSConfig` arrives, `apply(_:)` merges its overrides on top of the defaults;
/// flags the server doesn't mention keep their default value.
@MainActor
@Observable
public final class FeatureFlags {
    /// Known feature flags with their conservative default state.
    ///
    /// Defaults are deliberately safe: brand-new/risky surfaces default `false`
    /// (dark-launch, enable via remote config), stable ones default `true`.
    public enum Flag: String, CaseIterable, Sendable {
        case offlineReading = "offline_reading"
        case audioNarration = "audio_narration"
        case aiTutor = "ai_tutor"
        case social = "social"
        case widgets = "widgets"
        case liveActivities = "live_activities"
        case referrals = "referrals"

        /// The value used before any remote config is applied.
        public var defaultValue: Bool {
            switch self {
            case .offlineReading: return true
            case .audioNarration: return false
            case .aiTutor: return false
            case .social: return false
            case .widgets: return false
            case .liveActivities: return false
            case .referrals: return true
            }
        }
    }

    /// The default value for every known flag.
    public static let builtInDefaults: [String: Bool] = Dictionary(
        uniqueKeysWithValues: Flag.allCases.map { ($0.rawValue, $0.defaultValue) }
    )

    /// The currently-effective flag values (defaults merged with remote overrides).
    public private(set) var flags: [String: Bool]
    /// The most recently applied remote config, if any.
    public private(set) var config: IOSConfig?

    private let defaults: [String: Bool]

    public init(defaults: [String: Bool] = FeatureFlags.builtInDefaults) {
        self.defaults = defaults
        self.flags = defaults
    }

    /// Resolves a known flag, falling back to its built-in default and finally
    /// the case's `defaultValue` — so this is always safe to call.
    public func isEnabled(_ flag: Flag) -> Bool {
        flags[flag.rawValue] ?? defaults[flag.rawValue] ?? flag.defaultValue
    }

    /// Resolves an arbitrary flag key. Unknown keys default to `false`.
    public func isEnabled(_ key: String) -> Bool {
        flags[key] ?? defaults[key] ?? false
    }

    /// Merges a freshly-fetched remote config over the local defaults. Server
    /// values win; keys the server omits retain their default.
    public func apply(_ config: IOSConfig) {
        self.config = config
        var merged = defaults
        for (key, value) in config.featureFlags {
            merged[key] = value
        }
        self.flags = merged
    }

    /// Resets to built-in defaults (e.g. on sign-out).
    public func reset() {
        config = nil
        flags = defaults
    }
}
