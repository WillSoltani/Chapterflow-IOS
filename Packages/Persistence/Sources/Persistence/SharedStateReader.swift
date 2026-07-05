import Foundation

/// Reads the current ``SharedAppStateSnapshot`` from the App Group `UserDefaults` suite.
///
/// Extensions (widgets, Live Activities, watch) call ``load()`` to obtain the last
/// snapshot written by the main app. Reading is always synchronous and non-throwing:
/// any missing, corrupt, or unrecognised field degrades to a safe default rather than
/// crashing. An empty / never-written App Group returns an all-defaults snapshot.
///
/// ```swift
/// // Inside a WidgetKit timeline provider:
/// let snapshot = SharedStateReader().load()
/// Text("\(snapshot.streakDays) day streak")
/// ```
public struct SharedStateReader: @unchecked Sendable { // UserDefaults is thread-safe

    private let defaults: UserDefaults

    /// Creates a reader backed by the given `UserDefaults` suite name.
    ///
    /// - Parameter suiteName: Override for tests; uses the App Group suite by default.
    public init(suiteName: String? = nil) {
        self.defaults = UserDefaults(suiteName: suiteName ?? AppGroup.identifier) ?? .standard
    }

    // MARK: - Public API

    /// Loads and returns the latest snapshot from the App Group.
    ///
    /// Every field is read leniently — a missing or invalid value degrades to a
    /// sane default. This method never throws, never force-unwraps, never crashes.
    public func load() -> SharedAppStateSnapshot {
        let streakDays = max(0, defaults.integer(forKey: SharedStateKeys.streakDays))
        let streakAtRisk = defaults.bool(forKey: SharedStateKeys.streakAtRisk)
        let dueReviewCount = max(0, defaults.integer(forKey: SharedStateKeys.dueReviewCount))
        let rawGoal = defaults.object(forKey: SharedStateKeys.dailyGoalMinutes) as? Int
        let dailyGoalMinutes = rawGoal.map {
            DailyGoalStore.tiers.contains($0) ? $0 : DailyGoalStore.defaultGoalMinutes
        } ?? DailyGoalStore.defaultGoalMinutes
        let goalProgressMinutes = max(0, defaults.integer(forKey: SharedStateKeys.goalProgressMinutes))
        let continueBookId = defaults.string(forKey: SharedStateKeys.continueBookId)
        let continueBookTitle = defaults.string(forKey: SharedStateKeys.continueBookTitle)
        let continueBookCoverEmoji = defaults.string(forKey: SharedStateKeys.continueBookCoverEmoji)
        let continueBookCoverColor = defaults.string(forKey: SharedStateKeys.continueBookCoverColor)
        let continueChapterNumber = defaults.object(forKey: SharedStateKeys.continueChapterNumber) as? Int
        let continueProgress = (defaults.object(forKey: SharedStateKeys.continueProgress) as? Double)
            .map { max(0, min(1, $0)) }
        let rawTimestamp = defaults.object(forKey: SharedStateKeys.lastUpdated) as? Double
        let lastUpdated = rawTimestamp.map { Date(timeIntervalSince1970: $0) } ?? .distantPast

        return SharedAppStateSnapshot(
            streakDays: streakDays,
            streakAtRisk: streakAtRisk,
            continueBookId: continueBookId,
            continueBookTitle: continueBookTitle,
            continueBookCoverEmoji: continueBookCoverEmoji,
            continueBookCoverColor: continueBookCoverColor,
            continueChapterNumber: continueChapterNumber,
            continueProgress: continueProgress,
            dueReviewCount: dueReviewCount,
            dailyGoalMinutes: dailyGoalMinutes,
            goalProgressMinutes: goalProgressMinutes,
            lastUpdated: lastUpdated
        )
    }
}
