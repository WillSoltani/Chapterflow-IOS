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
}

/// A lightweight "continue reading" entry on the dashboard.
public struct DashboardBookEntry: Codable, Sendable {
    public let bookId: String
    public let title: String
    public let lastChapterNumber: Int
    public let cover: Cover?
}

public struct DashboardResponse: Codable, Sendable {
    public let dashboard: Dashboard
}
