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

/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed `/book/me/dashboard` is the WEB homepage aggregate —
/// `{catalog, entitlement, profile, settings, progress, bookStates,
/// chapterStates, saved, readingDays, badgeAwards, insightPointsBalance,
/// partial, warnings}` — with no `dashboard` key at all. This adapter
/// synthesizes the iOS `Dashboard` from that aggregate: `flowPoints` ←
/// `insightPointsBalance`, `booksStarted` ← the progress-entry count;
/// counters the aggregate cannot provide (streaks, reading minutes, due
/// reviews) default to 0 — the engagement UI overlays those from their
/// DEDICATED endpoints (`/me/streak`, `/me/reviews`, `/me/flow-points`),
/// so the zeros are placeholders, not displayed truth.
public struct DashboardResponse: Codable, Sendable {
    public let dashboard: Dashboard

    public init(dashboard: Dashboard) {
        self.dashboard = dashboard
    }

    private enum CodingKeys: String, CodingKey {
        case dashboard
        case insightPointsBalance, progress
    }

    private struct ProgressStub: Decodable {
        let bookId: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = container.decodeFirst(Dashboard.self, keys: [.dashboard]) {
            self.dashboard = wrapped
            return
        }
        let points = container.decodeFirst(Int.self, keys: [.insightPointsBalance]) ?? 0
        let started =
            ((try? container.decodeLossy(ProgressStub.self, forKey: .progress)) ?? []).count
        self.dashboard = Dashboard(
            currentStreak: 0,
            longestStreak: 0,
            todayReadingMinutes: 0,
            weeklyGoalMinutes: 0,
            weeklyReadMinutes: 0,
            booksStarted: started,
            booksCompleted: 0,
            flowPoints: points,
            tier: nil,
            tierProgress: nil,
            dueReviewCount: 0,
            continueBook: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dashboard, forKey: .dashboard)
    }
}
