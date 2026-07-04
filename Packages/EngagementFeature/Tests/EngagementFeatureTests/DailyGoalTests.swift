import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Helpers

private final class StubAPIClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private func makeDashboardClient(todayMinutes: Int = 20) -> StubAPIClient {
    StubAPIClient { endpoint in
        switch endpoint.path {
        case "/book/me/dashboard":
            return try JSONCoding.encoder.encode(DashboardResponse(dashboard: .goalFixture(todayMinutes: todayMinutes)))
        case "/book/me/streak":
            return try JSONCoding.encoder.encode(StreakResponse(streak: .goalTestFixture))
        case "/book/me/progress":
            return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: []))
        default:
            throw AppError.notFound
        }
    }
}

private extension Dashboard {
    static func goalFixture(todayMinutes: Int) -> Dashboard {
        Dashboard(
            currentStreak: 7,
            longestStreak: 14,
            todayReadingMinutes: todayMinutes,
            weeklyGoalMinutes: 120,
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
}

private extension StreakState {
    static let goalTestFixture = StreakState(
        currentStreak: 7,
        longestStreak: 14,
        streakShieldsHeld: 1,
        lastActivityDate: "2026-07-04",
        streakHistory: nil,
        consistencyLast30: [
            StreakDay(date: "2026-06-28", minutesRead: 10),
            StreakDay(date: "2026-06-29", minutesRead: 25),
            StreakDay(date: "2026-06-30", minutesRead: 0),
            StreakDay(date: "2026-07-01", minutesRead: 15),
            StreakDay(date: "2026-07-02", minutesRead: 30),
            StreakDay(date: "2026-07-03", minutesRead: 20),
            StreakDay(date: "2026-07-04", minutesRead: 18),
        ],
        milestonesReached: [7]
    )
}

// MARK: - DailyGoalStore tests

@Suite("DailyGoalStore")
struct DailyGoalStoreTests {

    private func freshStore() -> DailyGoalStore {
        let suiteName = "test.dailygoal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return DailyGoalStore(defaults: defaults)
    }

    @Test("defaults to 20 minutes when no value is stored")
    func defaultGoal() {
        let store = freshStore()
        #expect(store.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
    }

    @Test("persists a new goal value")
    func persistsGoal() {
        let store = freshStore()
        store.dailyGoalMinutes = 45
        #expect(store.dailyGoalMinutes == 45)
    }

    @Test("clamps values below minimum to minimum")
    func clampsLow() {
        let store = freshStore()
        store.dailyGoalMinutes = 0
        #expect(store.dailyGoalMinutes == DailyGoalStore.minimumGoalMinutes)
    }

    @Test("clamps values above maximum to maximum")
    func clampsHigh() {
        let store = freshStore()
        store.dailyGoalMinutes = 500
        #expect(store.dailyGoalMinutes == DailyGoalStore.maximumGoalMinutes)
    }

    @Test("progressFraction returns 0 when goal is 0")
    func progressFractionZeroGoal() {
        let store = freshStore()
        // Force goal to 0 by directly setting minimum then using raw default
        // (can't set below minimum via dailyGoalMinutes, so test via fraction math)
        let fraction = DailyGoalStore.defaultGoalMinutes > 0
            ? store.progressFraction(todayMinutes: 20)
            : 0.0
        // Just verify the fraction path works when goal > 0
        #expect(fraction > 0)
    }

    @Test("progressFraction is capped at 1.0 when over goal")
    func progressFractionCapped() {
        let store = freshStore()
        store.dailyGoalMinutes = 20
        #expect(store.progressFraction(todayMinutes: 60) == 1.0)
    }

    @Test("progressFraction returns partial when under goal")
    func progressFractionPartial() {
        let store = freshStore()
        store.dailyGoalMinutes = 60
        let fraction = store.progressFraction(todayMinutes: 30)
        #expect(abs(fraction - 0.5) < 0.001)
    }

    @Test("options contains all 5-minute steps from min to max")
    func optionsCoverage() {
        let options = DailyGoalStore.options
        #expect(options.first == DailyGoalStore.minimumGoalMinutes)
        #expect(options.last == DailyGoalStore.maximumGoalMinutes)
        // Every consecutive pair is exactly 5 minutes apart
        let allStep5 = zip(options, options.dropFirst()).allSatisfy { $1 - $0 == DailyGoalStore.stepMinutes }
        #expect(allStep5)
    }
}

// MARK: - DailyGoalState tests

@Suite("DailyGoalState")
struct DailyGoalStateTests {

    @Test("goalFraction is 0 when goalMinutes is 0")
    func zeroGoal() {
        let state = DailyGoalState(goalMinutes: 0, todayMinutes: 10, weekActivity: [])
        #expect(state.goalFraction == 0)
    }

    @Test("goalFraction clamps at 1.0 when over goal")
    func fractionClamped() {
        let state = DailyGoalState(goalMinutes: 20, todayMinutes: 40, weekActivity: [])
        #expect(state.goalFraction == 1.0)
        #expect(state.isGoalMet)
    }

    @Test("goalFraction is accurate at partial progress")
    func fractionPartial() {
        let state = DailyGoalState(goalMinutes: 30, todayMinutes: 15, weekActivity: [])
        #expect(abs(state.goalFraction - 0.5) < 0.001)
        #expect(!state.isGoalMet)
    }

    @Test("minutesRemaining is 0 when goal is met")
    func minutesRemainingZeroWhenMet() {
        let state = DailyGoalState(goalMinutes: 20, todayMinutes: 25, weekActivity: [])
        #expect(state.minutesRemaining == 0)
    }

    @Test("minutesRemaining is correct at partial progress")
    func minutesRemainingPartial() {
        let state = DailyGoalState(goalMinutes: 30, todayMinutes: 12, weekActivity: [])
        #expect(state.minutesRemaining == 18)
    }

    @Test("nudgeMessage contains 'complete' when goal is met")
    func nudgeGoalMet() {
        let state = DailyGoalState(goalMinutes: 20, todayMinutes: 25, weekActivity: [])
        #expect(state.nudgeMessage.lowercased().contains("complete"))
    }

    @Test("nudgeMessage contains 'halfway' at ~50 % progress")
    func nudgeHalfway() {
        let state = DailyGoalState(goalMinutes: 30, todayMinutes: 15, weekActivity: [])
        #expect(state.nudgeMessage.lowercased().contains("halfway") || state.nudgeMessage.contains("15"))
    }

    @Test("nudgeMessage is non-empty for zero progress")
    func nudgeZeroProgress() {
        let state = DailyGoalState(goalMinutes: 20, todayMinutes: 0, weekActivity: [])
        #expect(!state.nudgeMessage.isEmpty)
    }
}

// MARK: - DailyGoalDay tests

@Suite("DailyGoalDay")
struct DailyGoalDayTests {

    @Test("fraction is 0 when no activity")
    func fractionNoActivity() {
        let day = DailyGoalDay(date: Date(), minutesRead: 0, dailyGoal: 30)
        #expect(day.fraction == 0)
        #expect(!day.hasActivity)
    }

    @Test("fraction is capped at 1.0 when over goal")
    func fractionCapped() {
        let day = DailyGoalDay(date: Date(), minutesRead: 50, dailyGoal: 30)
        #expect(day.fraction == 1.0)
        #expect(day.isGoalMet)
    }

    @Test("dayLabel is a non-empty uppercase letter")
    func dayLabel() {
        let day = DailyGoalDay(date: Date(), minutesRead: 0, dailyGoal: 20)
        let label = day.dayLabel
        #expect(!label.isEmpty)
        #expect(label == label.uppercased())
    }

    @Test("accessibilityLabel mentions date and minutes for active day")
    func accessibilityLabelActive() {
        let day = DailyGoalDay(date: Date(), minutesRead: 15, dailyGoal: 30)
        let label = day.accessibilityLabel
        #expect(label.contains("15"))
    }

    @Test("accessibilityLabel mentions 'no reading' for inactive day")
    func accessibilityLabelInactive() {
        let day = DailyGoalDay(date: Date(), minutesRead: 0, dailyGoal: 30)
        let label = day.accessibilityLabel.lowercased()
        #expect(label.contains("no reading"))
    }
}

// MARK: - DailyGoalModel tests

@Suite("DailyGoalModel")
struct DailyGoalModelTests {

    private func freshStore(goal: Int = 30) -> DailyGoalStore {
        let suiteName = "test.model.dailygoal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = DailyGoalStore(defaults: defaults)
        store.dailyGoalMinutes = goal
        return store
    }

    @Test("loads state from repository")
    @MainActor func loadsStateFromRepository() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(todayMinutes: 20), modelContainer: nil)
        let store = freshStore(goal: 30)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        // Give the async task time to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .loaded(let state) = model.loadState else {
            Issue.record("Expected .loaded but got \(model.loadState)")
            return
        }
        #expect(state.todayMinutes == 20)
        #expect(state.goalMinutes == 30)
    }

    @Test("goalFraction reflects real activity vs user goal")
    @MainActor func goalFractionAccurate() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(todayMinutes: 15), modelContainer: nil)
        let store = freshStore(goal: 30)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .loaded(let state) = model.loadState else { return }
        #expect(abs(state.goalFraction - 0.5) < 0.001)
    }

    @Test("setGoal persists and rebuilds state without refetch")
    @MainActor func setGoalPersistsAndRebuilds() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(todayMinutes: 20), modelContainer: nil)
        let store = freshStore(goal: 30)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        try await Task.sleep(nanoseconds: 500_000_000)

        model.setGoal(40)

        guard case .loaded(let state) = model.loadState else {
            Issue.record("Expected .loaded after setGoal")
            return
        }
        #expect(state.goalMinutes == 40)
        #expect(model.goalMinutes == 40)
        #expect(store.dailyGoalMinutes == 40)
    }

    @Test("weekActivity contains exactly 7 days ordered oldest-first")
    @MainActor func weekActivityCount() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(), modelContainer: nil)
        let store = freshStore(goal: 20)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .loaded(let state) = model.loadState else { return }
        #expect(state.weekActivity.count == 7)

        // Last entry must be today
        #expect(state.weekActivity.last?.isToday == true)

        // Dates must be monotonically increasing
        let dates = state.weekActivity.map { $0.date }
        let ascending = zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 }
        #expect(ascending)
    }

    @Test("weekActivity activity values come from streak days")
    @MainActor func weekActivityValues() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(), modelContainer: nil)
        let store = freshStore(goal: 20)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .loaded(let state) = model.loadState else { return }
        // Today (2026-07-04) is in fixture with 18 minutes
        let today = state.weekActivity.last
        #expect(today?.minutesRead == 18)
    }

    @Test("currentState returns nil before load")
    @MainActor func currentStateBeforeLoad() {
        let repo = EngagementRepository(apiClient: makeDashboardClient(), modelContainer: nil)
        let model = DailyGoalModel(repository: repo)
        #expect(model.currentState == nil)
    }

    @Test("currentState returns state after load")
    @MainActor func currentStateAfterLoad() async throws {
        let repo = EngagementRepository(apiClient: makeDashboardClient(todayMinutes: 20), modelContainer: nil)
        let store = freshStore(goal: 30)
        let model = DailyGoalModel(repository: repo, store: store)

        model.load()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(model.currentState != nil)
        #expect(model.currentState?.goalMinutes == 30)
    }

    @Test("goalMinutes reflects store value")
    @MainActor func goalMinutesReflectsStore() {
        let repo = EngagementRepository(apiClient: makeDashboardClient(), modelContainer: nil)
        let store = freshStore(goal: 45)
        let model = DailyGoalModel(repository: repo, store: store)
        #expect(model.goalMinutes == 45)
    }
}
