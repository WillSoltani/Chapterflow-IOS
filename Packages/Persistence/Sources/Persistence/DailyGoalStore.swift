import Foundation

/// Persists the user's daily reading-goal preference (in minutes) to a shared
/// UserDefaults suite so that the main app, WidgetKit extensions, and the
/// notifications feature all read the same value.
///
/// ### Canonical model
/// The goal is expressed in minutes with exactly three tiers: 10, 20, and 30.
/// Values outside this set are snapped to the nearest tier on write.
///
/// ### Consumers
/// - `OnboardingFeature` — writes the user's chosen goal at onboarding time.
/// - `DailyGoalModel` — reads and writes the goal in the Engagement tab.
/// - Widgets (P8.1) — read `dailyGoalMinutes` + `progressFraction(todayMinutes:)`.
/// - Local reminders (P9.3) — read `dailyGoalMinutes` to set nudge thresholds.
public final class DailyGoalStore: @unchecked Sendable {

    // MARK: Shared singleton

    public static let shared = DailyGoalStore()

    // MARK: Constants

    /// App Group suite that both the main app and extensions share.
    public static let appGroupSuite = "group.com.chapterflow"

    /// UserDefaults key for the stored goal.
    public static let goalKey = "com.chapterflow.dailyGoalMinutes"

    /// The three valid goal tiers, in minutes.
    public static let tiers: [Int] = [10, 20, 30]

    /// Default goal tier (10 minutes).
    public static let defaultGoalMinutes = 10

    /// All valid goal options — same as `tiers`.
    public static var options: [Int] { tiers }

    // MARK: Storage

    private let defaults: UserDefaults
    private let key: String

    // MARK: Init

    /// Creates a store backed by the App Group suite; falls back to `.standard`
    /// in test/simulator environments where the group is unavailable.
    public init(defaults: UserDefaults? = nil, keyPrefix: String = "") {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupSuite)
            ?? .standard
        self.key = "\(keyPrefix)\(Self.goalKey)"
    }

    // MARK: - Public API

    /// The number of minutes in the user's daily reading goal.
    ///
    /// Always one of the three canonical tiers (10, 20, or 30).
    /// Writing a value outside the tier set snaps it to the nearest tier.
    public var dailyGoalMinutes: Int {
        get {
            let stored = defaults.integer(forKey: key)
            return Self.tiers.contains(stored) ? stored : Self.defaultGoalMinutes
        }
        set {
            let snapped = Self.tiers.min(by: { abs($0 - newValue) < abs($1 - newValue) }) ?? Self.defaultGoalMinutes
            defaults.set(snapped, forKey: key)
        }
    }

    /// Returns the fraction (0–1) of `todayMinutes` toward the stored goal.
    ///
    /// Capped at 1.0 to prevent the ring from overflowing.
    public func progressFraction(todayMinutes: Int) -> Double {
        let goal = dailyGoalMinutes
        guard goal > 0 else { return 0 }
        return min(1.0, Double(todayMinutes) / Double(goal))
    }
}
