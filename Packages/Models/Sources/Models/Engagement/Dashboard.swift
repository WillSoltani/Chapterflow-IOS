/// The user's progress dashboard — an aggregate view of their learning activity.
///
/// Returned by `GET /book/me/dashboard`.
public struct Dashboard: Codable, Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let todayReadingMinutes: Int
    public let weeklyGoalMinutes: Int
    public let weeklyReadMinutes: Int
    public let booksStarted: Int
    public let booksCompleted: Int
    public let flowPoints: Int
    public let tier: String?
    public let tierProgress: Double?
    public let dueReviewCount: Int
    public let continueBook: DashboardBookEntry?

    public init(
        currentStreak: Int,
        longestStreak: Int,
        todayReadingMinutes: Int,
        weeklyGoalMinutes: Int,
        weeklyReadMinutes: Int,
        booksStarted: Int,
        booksCompleted: Int,
        flowPoints: Int,
        tier: String?,
        tierProgress: Double?,
        dueReviewCount: Int,
        continueBook: DashboardBookEntry?
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.todayReadingMinutes = todayReadingMinutes
        self.weeklyGoalMinutes = weeklyGoalMinutes
        self.weeklyReadMinutes = weeklyReadMinutes
        self.booksStarted = booksStarted
        self.booksCompleted = booksCompleted
        self.flowPoints = flowPoints
        self.tier = tier
        self.tierProgress = tierProgress
        self.dueReviewCount = dueReviewCount
        self.continueBook = continueBook
    }
}

/// A lightweight "continue reading" entry on the dashboard.
public struct DashboardBookEntry: Codable, Sendable {
    public let bookId: String
    public let title: String
    public let lastChapterNumber: Int
    public let cover: Cover?

    public init(bookId: String, title: String, lastChapterNumber: Int, cover: Cover?) {
        self.bookId = bookId
        self.title = title
        self.lastChapterNumber = lastChapterNumber
        self.cover = cover
    }
}

public struct DashboardResponse: Codable, Sendable {
    public let dashboard: Dashboard

    public init(dashboard: Dashboard) {
        self.dashboard = dashboard
    }
}
