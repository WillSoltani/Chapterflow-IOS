import Foundation
import Models
import Networking
import CoreKit

// MARK: - Closure-based API client for previews

/// A closure-driven `APIClientProtocol` for previews.
/// (Separate from `Networking.MockAPIClient` which is an actor with per-path stubs.)
final class PreviewAPIClient: APIClientProtocol, @unchecked Sendable {
    private let handler: @Sendable (Endpoint) async throws -> Data

    init(handler: @escaping @Sendable (Endpoint) async throws -> Data) {
        self.handler = handler
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

// MARK: - Preview fixtures

extension Dashboard {
    static let preview = Dashboard(
        currentStreak: 14,
        longestStreak: 21,
        todayReadingMinutes: 25,
        weeklyGoalMinutes: 120,
        weeklyReadMinutes: 85,
        booksStarted: 6,
        booksCompleted: 3,
        flowPoints: 1_250,
        tier: "analyst",
        tierProgress: 0.62,
        dueReviewCount: 8,
        continueBook: DashboardBookEntry(
            bookId: "atomic-habits",
            title: "Atomic Habits",
            lastChapterNumber: 7,
            cover: Cover(emoji: "⚡️", color: "#1A3B6E")
        )
    )
}

extension StreakState {
    static let preview = StreakState(
        currentStreak: 14,
        longestStreak: 21,
        streakShieldsHeld: 2,
        lastActivityDate: "2026-07-02",
        streakHistory: nil,
        consistencyLast30: Self.previewConsistencyDays(activeToday: true),
        milestonesReached: [7, 14]
    )

    static let previewAtRisk = StreakState(
        currentStreak: 5,
        longestStreak: 21,
        streakShieldsHeld: 1,
        lastActivityDate: "2026-07-01",
        streakHistory: nil,
        consistencyLast30: Self.previewConsistencyDays(activeToday: false),
        milestonesReached: []
    )

    static let previewNoStreak = StreakState(
        currentStreak: 0,
        longestStreak: 7,
        streakShieldsHeld: 0,
        lastActivityDate: nil,
        streakHistory: nil,
        consistencyLast30: [],
        milestonesReached: []
    )

    private static func previewConsistencyDays(activeToday: Bool) -> [StreakDay] {
        let base = [
            0, 18, 22, 0, 35, 15, 28, 0, 10, 40,
            25, 20, 30, 0, 45, 12, 8, 33, 0, 27,
            19, 42, 0, 15, 38, 24, 11, 0, 30, activeToday ? 25 : 0,
        ]
        return base.enumerated().map { index, minutes in
            // Compute date strings relative to 2026-07-02 (today in fixtures)
            let dayOffset = index - 29
            var comps = DateComponents()
            comps.year = 2026; comps.month = 7; comps.day = 2
            let base = Calendar.current.date(from: comps) ?? Date()
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: base) ?? base
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return StreakDay(date: f.string(from: date), minutesRead: minutes)
        }
    }
}

extension Array where Element == ProgressOverviewItem {
    static let preview: [ProgressOverviewItem] = [
        ProgressOverviewItem(bookId: "atomic-habits", currentChapterNumber: 7, totalChapters: 12, completedChapterCount: 7, lastReadAt: "2026-07-02T14:30:00Z"),
        ProgressOverviewItem(bookId: "deep-work", currentChapterNumber: 10, totalChapters: 10, completedChapterCount: 10, lastReadAt: "2026-06-28T09:00:00Z"),
        ProgressOverviewItem(bookId: "thinking-fast-and-slow", currentChapterNumber: 5, totalChapters: 14, completedChapterCount: 5, lastReadAt: "2026-06-20T18:00:00Z"),
        ProgressOverviewItem(bookId: "psychology-of-money", currentChapterNumber: 2, totalChapters: 20, completedChapterCount: 2, lastReadAt: "2026-06-15T10:00:00Z"),
        ProgressOverviewItem(bookId: "the-power-of-habit", currentChapterNumber: 12, totalChapters: 12, completedChapterCount: 12, lastReadAt: "2026-05-30T08:00:00Z"),
        ProgressOverviewItem(bookId: "essentialism", currentChapterNumber: 0, totalChapters: 15, completedChapterCount: 0, lastReadAt: nil),
    ]
}

// MARK: - Preview EngagementRepository

extension EngagementRepository {
    /// An `EngagementRepository` pre-loaded with preview fixture data (no network, no disk).
    static var preview: EngagementRepository {
        makePreviewRepository(streak: .preview)
    }

    /// Repository where the streak has not been updated today (at-risk scenario).
    static var previewAtRisk: EngagementRepository {
        makePreviewRepository(streak: .previewAtRisk)
    }

    /// Repository where the user has no active streak.
    static var previewNoStreak: EngagementRepository {
        makePreviewRepository(streak: .previewNoStreak)
    }

    private static func makePreviewRepository(streak: StreakState) -> EngagementRepository {
        let dashboard = Dashboard.preview
        let progress: [ProgressOverviewItem] = .preview
        let client = PreviewAPIClient { endpoint in
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
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - AppError preview helper

extension AppError {
    static var preview: AppError { .offline }
}
