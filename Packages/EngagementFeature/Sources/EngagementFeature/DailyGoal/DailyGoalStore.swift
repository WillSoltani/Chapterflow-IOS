import Foundation

/// Persists the user's daily reading-goal preference (in minutes) to a shared
/// UserDefaults suite so that the main app, WidgetKit extensions, and the
/// notifications feature all read the same value.
///
/// Thread-safety: `UserDefaults` is documented as thread-safe; `DailyGoalStore`
/// is therefore `@unchecked Sendable`.
///
/// ### Consumers
/// - ``DailyGoalModel`` — reads and writes the goal.
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

    public static let defaultGoalMinutes = 20
    public static let minimumGoalMinutes = 5
    public static let maximumGoalMinutes = 120
    public static let stepMinutes = 5

    // MARK: Storage

    private let defaults: UserDefaults

    // MARK: Init

    /// Creates a store backed by the App Group suite; falls back to `.standard`
    /// in test/simulator environments where the group is unavailable.
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupSuite)
            ?? .standard
    }

    // MARK: - Public API

    /// The number of minutes in the user's daily reading goal.
    ///
    /// Setting this immediately persists to the shared `UserDefaults` suite.
    /// Value is clamped to `minimumGoalMinutes…maximumGoalMinutes` on write.
    public var dailyGoalMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Self.goalKey)
            return stored >= Self.minimumGoalMinutes ? stored : Self.defaultGoalMinutes
        }
        set {
            let clamped = max(Self.minimumGoalMinutes, min(Self.maximumGoalMinutes, newValue))
            defaults.set(clamped, forKey: Self.goalKey)
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

    /// All valid goal options in 5-minute steps.
    public static let options: [Int] = Array(stride(from: minimumGoalMinutes,
                                                     through: maximumGoalMinutes,
                                                     by: stepMinutes))
}
