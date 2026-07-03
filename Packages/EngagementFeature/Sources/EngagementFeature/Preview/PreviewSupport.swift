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

extension Array where Element == BadgeItem {
    static let preview: [BadgeItem] = [
        // Mastery track — earned
        BadgeItem(badgeId: "m-first-chapter", name: "First Chapter", description: "Read your very first chapter.", category: "mastery", isEarned: true, earnedAt: "2026-05-10T09:00:00Z", icon: "📖"),
        BadgeItem(badgeId: "m-deep-thinker", name: "Deep Thinker", description: "Complete 5 books end-to-end.", category: "mastery", isEarned: true, earnedAt: "2026-06-15T14:30:00Z", icon: "🧠"),
        // Mastery track — locked with progress
        BadgeItem(badgeId: "m-polymath", name: "Polymath", description: "Complete 10 books across 5 categories.", category: "mastery", isEarned: false, earnedAt: nil, icon: "🎓", progress: 6, target: 10),
        BadgeItem(badgeId: "m-scholar", name: "Scholar", description: "Answer 500 quiz questions correctly.", category: "mastery", isEarned: false, earnedAt: nil, icon: "🔬", progress: 312, target: 500),

        // Consistency track — earned
        BadgeItem(badgeId: "c-7-day", name: "Week Warrior", description: "Maintain a 7-day reading streak.", category: "consistency", isEarned: true, earnedAt: "2026-06-01T08:00:00Z", icon: "🔥"),
        // Consistency track — locked with progress
        BadgeItem(badgeId: "c-30-day", name: "Monthly Master", description: "Maintain a 30-day reading streak.", category: "consistency", isEarned: false, earnedAt: nil, icon: "📅", progress: 14, target: 30),
        BadgeItem(badgeId: "c-100-day", name: "Centurion", description: "Maintain a 100-day reading streak.", category: "consistency", isEarned: false, earnedAt: nil, icon: "💯", progress: 14, target: 100),

        // Exploration track — earned
        BadgeItem(badgeId: "e-genre-hopper", name: "Genre Hopper", description: "Read books from 3 different categories.", category: "exploration", isEarned: true, earnedAt: "2026-06-20T11:00:00Z", icon: "🗺️"),
        // Exploration track — locked
        BadgeItem(badgeId: "e-world-reader", name: "World Reader", description: "Read books from 8 different categories.", category: "exploration", isEarned: false, earnedAt: nil, icon: "🌍", progress: 4, target: 8),

        // Hidden track — earned (reveal all details)
        BadgeItem(badgeId: "h-night-owl", name: "Night Owl", description: "Read past midnight 5 times.", category: "hidden", isEarned: true, earnedAt: "2026-06-28T00:15:00Z", icon: "🦉"),
        // Hidden track — locked (stay mysterious)
        BadgeItem(badgeId: "h-secret-1", name: "???", description: "Secret criteria.", category: "hidden", isEarned: false, earnedAt: nil, icon: nil),
        BadgeItem(badgeId: "h-secret-2", name: "???", description: "Secret criteria.", category: "hidden", isEarned: false, earnedAt: nil, icon: nil),
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
        let badges: [BadgeItem] = .preview
        let client = PreviewAPIClient { endpoint in
            switch endpoint.path {
            case "/book/me/dashboard":
                return try JSONCoding.encoder.encode(DashboardResponse(dashboard: dashboard))
            case "/book/me/streak":
                return try JSONCoding.encoder.encode(StreakResponse(streak: streak))
            case "/book/me/progress":
                return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: progress))
            case "/book/me/badges":
                return try JSONCoding.encoder.encode(BadgesResponse(badges: badges))
            default:
                throw AppError.notFound
            }
        }
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - Preview BadgesModel

extension BadgesModel {
    /// A `BadgesModel` pre-loaded with fixture badges (no network, no disk).
    static var preview: BadgesModel {
        BadgesModel(repository: .preview, presenter: nil)
    }

    /// A `BadgesModel` in the error state for previewing the error UI.
    @MainActor static var previewError: BadgesModel {
        let model = BadgesModel(repository: .previewOffline, presenter: nil)
        return model
    }
}

extension EngagementRepository {
    /// An `EngagementRepository` that always throws `.offline` — for error previews.
    static var previewOffline: EngagementRepository {
        let client = PreviewAPIClient { _ in throw AppError.offline }
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - AppError preview helper

extension AppError {
    static var preview: AppError { .offline }
}
