import Foundation
import Observation
import CoreKit
import Models

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Milestone constants

let streakMilestoneDays = [7, 14, 30, 60, 100, 365]

// MARK: - HeatmapDay

/// A single day in the 30-day reading heatmap.
public struct HeatmapDay: Sendable {
    public let date: Date
    public let minutesRead: Int

    public var hasActivity: Bool { minutesRead > 0 }

    /// Heat intensity 0–1 (capped at 60 minutes = full intensity).
    public var intensity: Double {
        guard minutesRead > 0 else { return 0 }
        return min(1.0, Double(minutesRead) / 60.0)
    }

    public var accessibilityLabel: String {
        let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
        if minutesRead == 0 {
            return "\(dateStr): no reading"
        }
        return "\(dateStr): \(minutesRead) \(minutesRead == 1 ? "minute" : "minutes")"
    }
}

// MARK: - StreakModel

/// View model for the streak screen.
///
/// Loads streak data from ``EngagementRepository``, derives heatmap and milestone
/// state, detects the "at-risk" condition late in the day, and fires a one-per-day
/// celebration through ``CelebrationPresenter`` when the user's first daily activity
/// arrives.
@Observable
@MainActor
public final class StreakModel {

    // MARK: Nested types

    public enum LoadState {
        case loading
        case loaded(StreakState)
        case error(AppError)
    }

    // MARK: Public state

    public private(set) var loadState: LoadState = .loading
    public private(set) var isRefreshing = false

    // MARK: Dependencies

    private let repository: EngagementRepository
    private let celebrationPresenter: CelebrationPresenter
    private let userDefaults: UserDefaults

    // MARK: Internal state

    nonisolated(unsafe) private var loadTask: Task<Void, Never>?

    // MARK: Constants

    /// UserDefaults key storing the ISO-8601 date of the last celebration.
    static let celebrationDateKey = "com.chapterflow.streak.lastCelebrationDate"

    /// Hour-of-day (local) at which the streak is considered "at risk".
    static let atRiskHour = 20

    // MARK: Init

    public init(
        repository: EngagementRepository,
        celebrationPresenter: CelebrationPresenter,
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.celebrationPresenter = celebrationPresenter
        self.userDefaults = userDefaults
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

    // MARK: - Derived state

    /// 30-day heatmap ordered oldest → newest, padded with zero-minute days.
    public var heatmapDays: [HeatmapDay] {
        guard case .loaded(let streak) = loadState else { return [] }
        let days = streak.consistencyLast30 ?? streak.streakHistory ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).reversed().map { offset in
            // swiftlint:disable:next force_unwrapping
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dateStr = Self.iso8601String(from: date)
            let match = days.first { $0.date == dateStr }
            return HeatmapDay(date: date, minutesRead: match?.minutesRead ?? 0)
        }
    }

    /// True when the streak is > 0, no activity has landed today, and it's past 8 pm.
    public var isAtRisk: Bool {
        guard case .loaded(let streak) = loadState,
              streak.currentStreak > 0 else { return false }

        let today = Self.iso8601String(from: Calendar.current.startOfDay(for: Date()))
        if let lastActivity = streak.lastActivityDate, lastActivity >= today {
            return false // already read today
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= Self.atRiskHour
    }

    /// Milestones the user has already crossed (derived from server data or currentStreak).
    public var reachedMilestones: [Int] {
        guard case .loaded(let streak) = loadState else { return [] }
        if let fromServer = streak.milestonesReached { return fromServer }
        return streakMilestoneDays.filter { $0 <= streak.currentStreak }
    }

    /// The next milestone the user is working toward, or nil if all are done.
    public var nextMilestone: Int? {
        guard case .loaded(let streak) = loadState else { return nil }
        return streakMilestoneDays.first { $0 > streak.currentStreak }
    }

    /// Progress (0–1) toward the next milestone.
    public var nextMilestoneProgress: Double {
        guard case .loaded(let streak) = loadState,
              let next = nextMilestone else { return 1.0 }
        let previous = reachedMilestones.last ?? 0
        let range = next - previous
        guard range > 0 else { return 1.0 }
        return Double(streak.currentStreak - previous) / Double(range)
    }

    // MARK: - Private load

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            let streak = try await repository.fetchStreak(forceRefresh: forceRefresh)
            loadState = .loaded(streak)
            checkAndFireCelebration(streak)
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    // MARK: - Celebration guard (once per calendar day)

    /// Fires a streak-increment or milestone celebration at most once per calendar day,
    /// only when the day's first activity has landed.
    private func checkAndFireCelebration(_ streak: StreakState) {
        guard streak.currentStreak > 0 else { return }

        let today = Self.iso8601String(from: Calendar.current.startOfDay(for: Date()))

        // Require that the server reports activity today.
        guard let lastActivity = streak.lastActivityDate, lastActivity >= today else { return }

        guard userDefaults.string(forKey: Self.celebrationDateKey) != today else { return }

        // Record celebration date before presenting to guard against re-entry.
        userDefaults.set(today, forKey: Self.celebrationDateKey)

        fireHaptic()

        if streakMilestoneDays.contains(streak.currentStreak) {
            celebrationPresenter.enqueue(.streakMilestone(streak: streak.currentStreak))
        } else {
            celebrationPresenter.enqueue(.streakIncrement(newStreak: streak.currentStreak))
        }
        celebrationPresenter.present()
    }

    private func fireHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    // MARK: - Date utilities

    nonisolated static func iso8601String(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
