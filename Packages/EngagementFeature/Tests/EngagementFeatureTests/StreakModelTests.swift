import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Test helpers

private final class StubAPIClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private func makeStreakRepository(streak: StreakState) -> EngagementRepository {
    let client = StubAPIClient { endpoint in
        switch endpoint.path {
        case "/book/me/streak":
            return try JSONCoding.encoder.encode(StreakResponse(streak: streak))
        default:
            throw AppError.notFound
        }
    }
    return EngagementRepository(apiClient: client, modelContainer: nil)
}

/// Builds a StreakState where `lastActivityDate` is today.
private func streakWithActivityToday(currentStreak: Int = 5) -> StreakState {
    let today = StreakModel.iso8601String(from: Calendar.current.startOfDay(for: Date()))
    return StreakState(
        currentStreak: currentStreak,
        longestStreak: 21,
        streakShieldsHeld: 2,
        lastActivityDate: today,
        streakHistory: nil,
        consistencyLast30: nil,
        milestonesReached: nil
    )
}

/// Builds a StreakState where `lastActivityDate` is yesterday.
private func streakWithActivityYesterday(currentStreak: Int = 3) -> StreakState {
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let dateStr = StreakModel.iso8601String(from: yesterday)
    return StreakState(
        currentStreak: currentStreak,
        longestStreak: 10,
        streakShieldsHeld: 1,
        lastActivityDate: dateStr,
        streakHistory: nil,
        consistencyLast30: nil,
        milestonesReached: nil
    )
}

// MARK: - HeatmapDay tests

@Suite("HeatmapDay")
struct HeatmapDayTests {

    @Test("hasActivity is false when minutesRead is zero")
    func noActivity() {
        let day = HeatmapDay(date: Date(), minutesRead: 0)
        #expect(!day.hasActivity)
        #expect(day.intensity == 0)
    }

    @Test("hasActivity is true when minutesRead is positive")
    func withActivity() {
        let day = HeatmapDay(date: Date(), minutesRead: 30)
        #expect(day.hasActivity)
        #expect(day.intensity > 0)
    }

    @Test("intensity clamps at 1.0 for 60+ minutes")
    func intensityClamped() {
        let day = HeatmapDay(date: Date(), minutesRead: 120)
        #expect(day.intensity == 1.0)
    }

    @Test("intensity is proportional below cap")
    func intensityProportional() {
        let day = HeatmapDay(date: Date(), minutesRead: 30)
        #expect(abs(day.intensity - 0.5) < 0.001)
    }

    @Test("accessibilityLabel describes zero-minute day")
    func zeroLabel() {
        let day = HeatmapDay(date: Date(), minutesRead: 0)
        #expect(day.accessibilityLabel.contains("no reading"))
    }

    @Test("accessibilityLabel describes active day")
    func activeLabel() {
        let day = HeatmapDay(date: Date(), minutesRead: 15)
        #expect(day.accessibilityLabel.contains("15"))
    }
}

// MARK: - StreakModel.isAtRisk tests

@Suite("StreakModel isAtRisk")
@MainActor
struct StreakModelAtRiskTests {

    @Test("not at risk when streak is zero")
    func zeroStreak() async {
        let streak = StreakState(
            currentStreak: 0, longestStreak: 0, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        _ = try? await repo.fetchStreak()
        // Load state manually
        sut.load()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!sut.isAtRisk)
    }

    @Test("not at risk when activity landed today")
    func activityToday() async throws {
        let streak = streakWithActivityToday()
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        // Activity today → never at risk regardless of hour
        #expect(!sut.isAtRisk)
    }
}

// MARK: - StreakModel milestone derivation tests

@Suite("StreakModel milestone derivation")
@MainActor
struct StreakModelMilestoneTests {

    @Test("reachedMilestones uses server list when available")
    func serverMilestones() async throws {
        let streak = StreakState(
            currentStreak: 14, longestStreak: 30, streakShieldsHeld: 2,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: nil, milestonesReached: [7, 14]
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(sut.reachedMilestones == [7, 14])
    }

    @Test("reachedMilestones derives from currentStreak when server list is nil")
    func derivedMilestones() async throws {
        let streak = StreakState(
            currentStreak: 30, longestStreak: 30, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: nil, milestonesReached: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(sut.reachedMilestones == [7, 14, 30])
    }

    @Test("nextMilestone returns the smallest uncrossed threshold")
    func nextMilestone() async throws {
        let streak = StreakState(
            currentStreak: 15, longestStreak: 20, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: nil, milestonesReached: [7, 14]
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(sut.nextMilestone == 30)
    }

    @Test("nextMilestone is nil when all milestones passed")
    func allMilestonesDone() async throws {
        let streak = StreakState(
            currentStreak: 400, longestStreak: 400, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: nil, milestonesReached: [7, 14, 30, 60, 100, 365]
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(sut.nextMilestone == nil)
    }

    @Test("nextMilestoneProgress is 0 at start of interval")
    func progressAtStart() async throws {
        let streak = StreakState(
            currentStreak: 7, longestStreak: 7, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: nil, milestonesReached: [7]
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        // Next milestone is 14; current is 7; previous is 7 → progress = (7-7)/(14-7) = 0
        #expect(abs(sut.nextMilestoneProgress - 0.0) < 0.001)
    }
}

// MARK: - StreakModel heatmap tests

@Suite("StreakModel heatmap")
@MainActor
struct StreakModelHeatmapTests {

    @Test("heatmapDays always returns 30 entries")
    func alwaysThirtyDays() async throws {
        let days = (0..<15).map { offset -> StreakDay in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            return StreakDay(date: StreakModel.iso8601String(from: date), minutesRead: 10)
        }
        let streak = StreakState(
            currentStreak: 15, longestStreak: 15, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil,
            consistencyLast30: days, milestonesReached: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(sut.heatmapDays.count == 30)
    }

    @Test("heatmapDays prefers consistencyLast30 over streakHistory")
    func prefersConsistencyLast30() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let todayStr = StreakModel.iso8601String(from: today)

        let streak = StreakState(
            currentStreak: 1, longestStreak: 1, streakShieldsHeld: 0,
            lastActivityDate: todayStr,
            streakHistory: [StreakDay(date: todayStr, minutesRead: 5)],
            consistencyLast30: [StreakDay(date: todayStr, minutesRead: 42)],
            milestonesReached: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        // The last day (index 29 = today) should reflect consistencyLast30, not streakHistory
        #expect(sut.heatmapDays.last?.minutesRead == 42)
    }

    @Test("missing days in server data are padded with 0 minutes")
    func paddedMissingDays() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let todayStr = StreakModel.iso8601String(from: today)

        let streak = StreakState(
            currentStreak: 1, longestStreak: 1, streakShieldsHeld: 0,
            lastActivityDate: todayStr,
            streakHistory: nil,
            consistencyLast30: [StreakDay(date: todayStr, minutesRead: 20)],
            milestonesReached: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        // All days except today should have 0 minutes
        let zeros = sut.heatmapDays.dropLast().filter { !$0.hasActivity }
        #expect(zeros.count == 29)
    }
}

// MARK: - Once-per-day celebration guard tests

/// Provides an isolated UserDefaults suite so parallel tests do not share state.
private func isolatedDefaults() -> UserDefaults {
    // Use a UUID-based suite name to guarantee each call gets a fresh store.
    let suite = "com.chapterflow.test.\(UUID().uuidString)"
    // swiftlint:disable:next force_unwrapping
    return UserDefaults(suiteName: suite)!
}

@Suite("StreakModel once-per-day celebration guard")
@MainActor
struct StreakModelCelebrationGuardTests {

    @Test("celebration fires on first load when activity is today")
    func firesOnFirstLoad() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = streakWithActivityToday(currentStreak: 5)
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(presenter.isPresenting, "Celebration should fire on first load with today's activity")
    }

    @Test("celebration does not fire on second load the same calendar day")
    func doesNotFireTwice() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = streakWithActivityToday(currentStreak: 5)
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)

        // First load
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        presenter.dismissAll()

        // Second load (refresh)
        await sut.refresh()
        #expect(!presenter.isPresenting, "Second load must not re-fire the celebration")
    }

    @Test("no celebration when streak is zero")
    func noFireWhenZeroStreak() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = StreakState(
            currentStreak: 0, longestStreak: 5, streakShieldsHeld: 0,
            lastActivityDate: nil, streakHistory: nil
        )
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!presenter.isPresenting)
    }

    @Test("no celebration when lastActivityDate is yesterday")
    func noFireWhenYesterdayActivity() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = streakWithActivityYesterday()
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!presenter.isPresenting)
    }

    @Test("milestone event fires instead of increment on milestone day")
    func milestoneEventOnMilestoneDay() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = streakWithActivityToday(currentStreak: 7) // 7 = first milestone
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(presenter.currentEvent == .streakMilestone(streak: 7))
    }

    @Test("regular increment event fires on non-milestone day")
    func incrementEventOnNormalDay() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let streak = streakWithActivityToday(currentStreak: 5) // 5 is not a milestone
        let repo = makeStreakRepository(streak: streak)
        let sut = StreakModel(repository: repo, celebrationPresenter: presenter, userDefaults: defaults)
        sut.load()
        try await Task.sleep(for: .milliseconds(150))
        #expect(presenter.currentEvent == .streakIncrement(newStreak: 5))
    }
}

// MARK: - StreakState model decoding tests

@Suite("StreakState tolerant decoding")
struct StreakStateDecodingTests {

    @Test("decodes consistencyLast30 and milestonesReached when present")
    func decodesNewFields() throws {
        let json = """
        {
            "streak": {
                "currentStreak": 14,
                "longestStreak": 30,
                "streakShieldsHeld": 2,
                "lastActivityDate": "2026-07-02",
                "consistencyLast30": [
                    {"date": "2026-07-01", "minutesRead": 20},
                    {"date": "2026-07-02", "minutesRead": 35}
                ],
                "milestonesReached": [7, 14]
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(StreakResponse.self, from: json)
        #expect(resp.streak.consistencyLast30?.count == 2)
        #expect(resp.streak.milestonesReached == [7, 14])
        #expect(resp.streak.currentStreak == 14)
    }

    @Test("decodes without new fields (backward compatible)")
    func decodesWithoutNewFields() throws {
        let json = """
        {
            "streak": {
                "currentStreak": 3,
                "longestStreak": 8,
                "streakShieldsHeld": 0,
                "lastActivityDate": null
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(StreakResponse.self, from: json)
        #expect(resp.streak.consistencyLast30 == nil)
        #expect(resp.streak.milestonesReached == nil)
        #expect(resp.streak.currentStreak == 3)
    }

    @Test("decodes with unknown future fields without crashing")
    func toleratesUnknownFields() throws {
        let json = """
        {
            "streak": {
                "currentStreak": 5,
                "longestStreak": 10,
                "streakShieldsHeld": 1,
                "lastActivityDate": "2026-07-02",
                "newFieldFromFuture": "should be ignored",
                "anotherNewField": 42
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(StreakResponse.self, from: json)
        #expect(resp.streak.currentStreak == 5)
    }
}
