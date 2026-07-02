import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Helpers

/// Thread-safe mutable box for capturing counters/flags in @Sendable closures.
private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class StubAPIClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

private func makeDashboardClient(
    dashboard: Dashboard = .fixture,
    streak: StreakState = .fixture,
    progress: [ProgressOverviewItem] = .fixture
) -> StubAPIClient {
    StubAPIClient { endpoint in
        switch endpoint.path {
        case "/book/me/dashboard":
            return try JSONCoding.encoder.encode(DashboardResponse(dashboard: dashboard))
        case "/book/me/streak":
            return try JSONCoding.encoder.encode(StreakResponse(streak: streak))
        case "/book/me/progress":
            return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: progress))
        default:
            throw AppError.notFound
        }
    }
}

// MARK: - Fixture extensions

extension Dashboard {
    static let fixture = Dashboard(
        currentStreak: 7,
        longestStreak: 14,
        todayReadingMinutes: 20,
        weeklyGoalMinutes: 100,
        weeklyReadMinutes: 60,
        booksStarted: 4,
        booksCompleted: 2,
        flowPoints: 500,
        tier: "analyst",
        tierProgress: 0.40,
        dueReviewCount: 3,
        continueBook: nil
    )
}

extension StreakState {
    static let fixture = StreakState(
        currentStreak: 7,
        longestStreak: 14,
        streakShieldsHeld: 1,
        lastActivityDate: "2026-07-01",
        streakHistory: [
            StreakDay(date: "2026-06-26", minutesRead: 10),
            StreakDay(date: "2026-06-27", minutesRead: 20),
            StreakDay(date: "2026-06-28", minutesRead: 0),
            StreakDay(date: "2026-06-29", minutesRead: 15),
            StreakDay(date: "2026-06-30", minutesRead: 25),
            StreakDay(date: "2026-07-01", minutesRead: 20),
            StreakDay(date: "2026-07-02", minutesRead: 10),
        ]
    )
}

extension Array where Element == ProgressOverviewItem {
    static let fixture: [ProgressOverviewItem] = [
        ProgressOverviewItem(bookId: "book-a", currentChapterNumber: 5, totalChapters: 10, completedChapterCount: 5, lastReadAt: nil),
        ProgressOverviewItem(bookId: "book-b", currentChapterNumber: 10, totalChapters: 10, completedChapterCount: 10, lastReadAt: nil),
        ProgressOverviewItem(bookId: "book-c", currentChapterNumber: 0, totalChapters: 8, completedChapterCount: 0, lastReadAt: nil),
    ]
}

// MARK: - Repository tests

@Suite("EngagementRepository")
struct EngagementRepositoryTests {

    @Test("fetchDashboardSnapshot parallel-fetches all three resources")
    func fetchDashboardSnapshot() async throws {
        let client = makeDashboardClient()
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        let snapshot = try await repo.fetchDashboardSnapshot()

        #expect(snapshot.dashboard.currentStreak == 7)
        #expect(snapshot.streak.currentStreak == 7)
        #expect(snapshot.progress.count == 3)
    }

    @Test("fetchDashboard returns cached value within TTL")
    func fetchDashboardCachesResult() async throws {
        let callCount = Box(0)
        let client = StubAPIClient { endpoint in
            if endpoint.path == "/book/me/dashboard" {
                callCount.value += 1
                return try JSONCoding.encoder.encode(DashboardResponse(dashboard: .fixture))
            }
            if endpoint.path == "/book/me/streak" {
                return try JSONCoding.encoder.encode(StreakResponse(streak: .fixture))
            }
            return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: []))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchDashboard()
        _ = try await repo.fetchDashboard()

        #expect(callCount.value == 1, "Second call should hit the in-memory cache")
    }

    @Test("fetchDashboard forceRefresh bypasses in-memory cache")
    func fetchDashboardForceRefresh() async throws {
        let callCount = Box(0)
        let client = StubAPIClient { endpoint in
            if endpoint.path == "/book/me/dashboard" {
                callCount.value += 1
                return try JSONCoding.encoder.encode(DashboardResponse(dashboard: .fixture))
            }
            if endpoint.path == "/book/me/streak" {
                return try JSONCoding.encoder.encode(StreakResponse(streak: .fixture))
            }
            return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: []))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchDashboard()
        _ = try await repo.fetchDashboard(forceRefresh: true)

        #expect(callCount.value == 2, "Force refresh must bypass the in-memory cache")
    }

    @Test("derived accessor flowPointsBalance reflects last-fetched dashboard")
    func flowPointsBalance() async throws {
        let client = makeDashboardClient()
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        #expect(await repo.flowPointsBalance == nil, "Should be nil before first fetch")

        _ = try await repo.fetchDashboard()
        #expect(await repo.flowPointsBalance == 500)
    }

    @Test("derived accessor tier reflects last-fetched dashboard")
    func tierAccessor() async throws {
        let client = makeDashboardClient()
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchDashboard()
        #expect(await repo.tier == "analyst")
        #expect(await repo.tierProgress == 0.40)
    }

    @Test("invalidateAll clears all in-memory state")
    func invalidateAll() async throws {
        let client = makeDashboardClient()
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchDashboard()
        #expect(await repo.currentDashboard != nil)

        await repo.invalidateAll()
        #expect(await repo.currentDashboard == nil)
    }

    @Test("offline error falls back to any in-memory cache")
    func offlineFallbackToMemory() async throws {
        let shouldFail = Box(false)
        let client = StubAPIClient { endpoint in
            if shouldFail.value { throw AppError.offline }
            if endpoint.path == "/book/me/dashboard" {
                return try JSONCoding.encoder.encode(DashboardResponse(dashboard: .fixture))
            }
            if endpoint.path == "/book/me/streak" {
                return try JSONCoding.encoder.encode(StreakResponse(streak: .fixture))
            }
            return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: []))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchDashboard()
        shouldFail.value = true

        // Should return stale cached value rather than throwing
        let dashboard = try await repo.fetchDashboard(forceRefresh: true)
        #expect(dashboard.currentStreak == 7)
    }

    @Test("offline error propagates when no cache exists")
    func offlineNoCachePropagates() async throws {
        let client = StubAPIClient { _ in throw AppError.offline }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        do {
            _ = try await repo.fetchDashboard()
            Issue.record("Should have thrown AppError.offline")
        } catch AppError.offline {
            // Expected
        }
    }
}

// MARK: - DashboardSnapshot tests

@Suite("DashboardSnapshot")
struct DashboardSnapshotTests {

    private let snapshot = DashboardSnapshot(
        dashboard: .fixture,
        streak: .fixture,
        progress: .fixture
    )

    @Test("totalChaptersCompleted sums all completed chapters")
    func totalChaptersCompleted() {
        // book-a: 5, book-b: 10, book-c: 0
        #expect(snapshot.totalChaptersCompleted == 15)
    }

    @Test("booksCompleted counts only fully-completed books")
    func booksCompleted() {
        // book-b has 10/10 chapters
        #expect(snapshot.booksCompleted == 1)
    }

    @Test("booksInProgress counts partially-completed books")
    func booksInProgress() {
        // book-a has 5/10
        #expect(snapshot.booksInProgress == 1)
    }

    @Test("booksNotStarted counts zero-completed books")
    func booksNotStarted() {
        // book-c has 0/8
        #expect(snapshot.booksNotStarted == 1)
    }

    @Test("weeklyGoalFraction clamps at 1.0 even when over goal")
    func weeklyGoalFractionClamped() {
        let overGoal = DashboardSnapshot(
            dashboard: Dashboard(
                currentStreak: 0, longestStreak: 0,
                todayReadingMinutes: 0, weeklyGoalMinutes: 50, weeklyReadMinutes: 200,
                booksStarted: 0, booksCompleted: 0, flowPoints: 0,
                tier: nil, tierProgress: nil, dueReviewCount: 0, continueBook: nil
            ),
            streak: .fixture,
            progress: []
        )
        #expect(overGoal.weeklyGoalFraction == 1.0)
    }

    @Test("weeklyGoalFraction is 0 when goal is 0")
    func weeklyGoalFractionZeroGoal() {
        let zeroGoal = DashboardSnapshot(
            dashboard: Dashboard(
                currentStreak: 0, longestStreak: 0,
                todayReadingMinutes: 0, weeklyGoalMinutes: 0, weeklyReadMinutes: 60,
                booksStarted: 0, booksCompleted: 0, flowPoints: 0,
                tier: nil, tierProgress: nil, dueReviewCount: 0, continueBook: nil
            ),
            streak: .fixture,
            progress: []
        )
        #expect(zeroGoal.weeklyGoalFraction == 0)
    }

    @Test("last14Days returns at most 14 days oldest-first")
    func last14Days() {
        // fixture has 7 days
        let days = snapshot.last14Days
        #expect(days.count == 7)
        // ordered oldest first (reversed from streakHistory suffix)
        #expect(days.first?.date == "2026-06-26")
        #expect(days.last?.date == "2026-07-02")
    }

    @Test("averageDailyMinutes computes correctly")
    func averageDailyMinutes() {
        // 10+20+0+15+25+20+10 = 100 / 7
        let expected = 100.0 / 7.0
        #expect(abs(snapshot.averageDailyMinutes - expected) < 0.01)
    }
}

// MARK: - Tolerant decoding tests

@Suite("EngagementRepository tolerant decoding")
struct EngagementRepositoryDecodingTests {

    @Test("DashboardResponse decodes with unknown future fields present")
    func dashboardToleratesUnknownFields() throws {
        let json = """
        {
            "dashboard": {
                "currentStreak": 5,
                "longestStreak": 10,
                "todayReadingMinutes": 15,
                "weeklyGoalMinutes": 60,
                "weeklyReadMinutes": 30,
                "booksStarted": 3,
                "booksCompleted": 1,
                "flowPoints": 200,
                "tier": "reader",
                "tierProgress": 0.25,
                "dueReviewCount": 2,
                "continueBook": null,
                "futureField": "should be ignored",
                "anotherNewField": 42
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(DashboardResponse.self, from: json)
        #expect(resp.dashboard.currentStreak == 5)
        #expect(resp.dashboard.tier == "reader")
    }

    @Test("StreakResponse decodes with null streakHistory")
    func streakToleratesNullHistory() throws {
        let json = """
        {
            "streak": {
                "currentStreak": 3,
                "longestStreak": 8,
                "streakShieldsHeld": 0,
                "lastActivityDate": null,
                "streakHistory": null
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(StreakResponse.self, from: json)
        #expect(resp.streak.streakHistory == nil)
        #expect(resp.streak.currentStreak == 3)
    }

    @Test("DashboardResponse decodes when optional continueBook is absent")
    func dashboardMissingOptionalFields() throws {
        let json = """
        {
            "dashboard": {
                "currentStreak": 1,
                "longestStreak": 1,
                "todayReadingMinutes": 5,
                "weeklyGoalMinutes": 60,
                "weeklyReadMinutes": 5,
                "booksStarted": 1,
                "booksCompleted": 0,
                "flowPoints": 0,
                "dueReviewCount": 0
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(DashboardResponse.self, from: json)
        #expect(resp.dashboard.continueBook == nil)
        #expect(resp.dashboard.tier == nil)
        #expect(resp.dashboard.tierProgress == nil)
    }

    @Test("ProgressOverviewResponse decodes lossily, surviving corrupt elements")
    func progressLossyDecode() throws {
        let json = """
        {
            "progress": [
                {
                    "bookId": "valid-book",
                    "currentChapterNumber": 3,
                    "totalChapters": 10,
                    "completedChapterCount": 3,
                    "lastReadAt": null
                },
                null,
                {
                    "bookId": "another-valid",
                    "currentChapterNumber": 1,
                    "totalChapters": 5,
                    "completedChapterCount": 1
                }
            ]
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(ProgressOverviewResponse.self, from: json)
        // The null element should be dropped; the two valid items should survive
        #expect(resp.progress.count == 2)
        #expect(resp.progress[0].bookId == "valid-book")
        #expect(resp.progress[1].bookId == "another-valid")
    }
}
