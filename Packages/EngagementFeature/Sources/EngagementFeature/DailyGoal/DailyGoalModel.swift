import Foundation
import Observation
import CoreKit
import Models
import Persistence

/// View model for the daily-goal & habit surface.
///
/// Loads today's reading minutes from ``EngagementRepository`` (via
/// `Dashboard.todayReadingMinutes`) and the seven-day activity array from
/// `StreakState.consistencyLast30` / `streakHistory`. The user's goal is read
/// from and written to ``DailyGoalStore``, which persists to the shared App
/// Group suite so widgets (P8.1) and reminders (P9.3) can observe it.
///
/// Changing the goal with ``setGoal(_:)`` immediately rebuilds the loaded state
/// without a round-trip to the network.
@Observable
@MainActor
public final class DailyGoalModel {

    // MARK: Load state

    public enum LoadState {
        case loading
        case loaded(DailyGoalState)
        case error(AppError)
    }

    // MARK: Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false

    /// The current goal in minutes, live-reflected from ``DailyGoalStore``.
    public var goalMinutes: Int { store.dailyGoalMinutes }

    // MARK: Dependencies

    private let repository: EngagementRepository
    private let store: DailyGoalStore

    // MARK: Cached raw values (for instant goal-change re-render)

    private var cachedTodayMinutes: Int?
    private var cachedStreakDays: [StreakDay] = []

    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: Init

    public init(repository: EngagementRepository, store: DailyGoalStore = .shared) {
        self.repository = repository
        self.store = store
    }

    deinit { loadTask?.cancel() }

    // MARK: - Intents

    public func load() {
        guard case .loading = loadState else { return }
        beginLoad()
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await performFetch(forceRefresh: true)
    }

    /// Persists a new goal and immediately updates the displayed state.
    ///
    /// Also publishes a partial ``SharedAppStateSnapshot`` update to the App Group
    /// via ``SharedStateWriter`` so widgets reflect the change without a full refresh.
    public func setGoal(_ minutes: Int) {
        store.dailyGoalMinutes = minutes
        rebuildState()
        let todayMinutes = cachedTodayMinutes ?? 0
        Task { await SharedStateWriter.shared.updateGoalState(goalMinutes: minutes, progressMinutes: todayMinutes) }
    }

    // MARK: - Exposed for widgets / reminders

    /// Returns the latest ``DailyGoalState`` without triggering a network fetch.
    ///
    /// Widgets and reminders can call this synchronously after the model has
    /// been loaded once; they should otherwise read directly from ``DailyGoalStore``.
    public var currentState: DailyGoalState? {
        if case .loaded(let s) = loadState { return s }
        return nil
    }

    // MARK: - Private

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            async let dashboard = repository.fetchDashboard(forceRefresh: forceRefresh)
            async let streak = repository.fetchStreak(forceRefresh: forceRefresh)
            let (d, s) = try await (dashboard, streak)

            cachedTodayMinutes = d.todayReadingMinutes
            cachedStreakDays = s.consistencyLast30 ?? s.streakHistory ?? []
            rebuildState()
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    private func rebuildState() {
        guard let todayMinutes = cachedTodayMinutes else { return }
        let goal = store.dailyGoalMinutes
        let week = buildWeekActivity(days: cachedStreakDays, goalMinutes: goal)
        loadState = .loaded(DailyGoalState(
            goalMinutes: goal,
            todayMinutes: todayMinutes,
            weekActivity: week
        ))
    }

    private func buildWeekActivity(days: [StreakDay], goalMinutes: Int) -> [DailyGoalDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            // swiftlint:disable:next force_unwrapping
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dateStr = Self.isoDateString(from: date)
            let match = days.first { $0.date == dateStr }
            return DailyGoalDay(date: date, minutesRead: match?.minutesRead ?? 0, dailyGoal: goalMinutes)
        }
    }

    // MARK: - Date utility

    nonisolated static func isoDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
