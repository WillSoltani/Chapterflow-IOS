import Models

/// An immutable aggregate of the three engagement endpoints fetched in parallel
/// for the progress dashboard.
public struct DashboardSnapshot: Sendable {
    public let dashboard: Dashboard
    public let streak: StreakState
    public let progress: [ProgressOverviewItem]

    public init(dashboard: Dashboard, streak: StreakState, progress: [ProgressOverviewItem]) {
        self.dashboard = dashboard
        self.streak = streak
        self.progress = progress
    }

    // MARK: - Derived aggregates

    /// Sum of completed chapters across all in-progress books.
    public var totalChaptersCompleted: Int {
        progress.reduce(0) { $0 + $1.completedChapterCount }
    }

    /// Total chapters available across all started books.
    public var totalChaptersAvailable: Int {
        progress.reduce(0) { $0 + $1.totalChapters }
    }

    /// Books the user has completed every chapter of.
    public var booksCompleted: Int {
        progress.filter { $0.completedChapterCount >= $0.totalChapters && $0.totalChapters > 0 }.count
    }

    /// Books with at least one chapter completed but not all.
    public var booksInProgress: Int {
        progress.filter { $0.completedChapterCount > 0 && $0.completedChapterCount < $0.totalChapters }.count
    }

    /// Books the user has started but not yet read a single chapter.
    public var booksNotStarted: Int {
        progress.filter { $0.completedChapterCount == 0 }.count
    }

    /// Daily reading history from the streak, ordered oldest-first (chronological).
    public var readingDays: [StreakDay] {
        streak.streakHistory ?? []
    }

    /// Last 7 days of reading activity, ordered oldest-first.
    public var last7Days: [StreakDay] {
        Array(readingDays.suffix(7))
    }

    /// Last 14 days of reading activity, ordered oldest-first for charts.
    public var last14Days: [StreakDay] {
        Array(readingDays.suffix(14))
    }

    /// Average minutes read per day over the available streak history.
    public var averageDailyMinutes: Double {
        let days = readingDays
        guard !days.isEmpty else { return 0 }
        let total = days.reduce(0) { $0 + $1.minutesRead }
        return Double(total) / Double(days.count)
    }

    /// Progress fraction (0–1) toward the weekly reading goal.
    public var weeklyGoalFraction: Double {
        guard dashboard.weeklyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(dashboard.weeklyReadMinutes) / Double(dashboard.weeklyGoalMinutes))
    }
}
