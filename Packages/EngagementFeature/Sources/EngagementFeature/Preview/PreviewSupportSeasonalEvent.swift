import Foundation
import Models
import Networking
import CoreKit

// MARK: - Seasonal Event fixtures

extension SeasonalEvent {
    static let preview = SeasonalEvent(
        eventId: "summer-reading-2026",
        title: "Summer Reading Challenge",
        description: "Read 20 chapters this July and earn the Summer Scholar badge.",
        startsAt: "2026-07-01T00:00:00Z",
        endsAt: "2026-07-31T23:59:59Z",
        targetChapters: 20,
        dailyTarget: 1,
        badge: BadgeItem(
            badgeId: "summer-scholar",
            name: "Summer Scholar",
            description: "Completed the Summer 2026 reading challenge.",
            category: "seasonal",
            isEarned: false,
            earnedAt: nil,
            icon: "☀️"
        ),
        bonusIp: 500,
        isActive: true,
        hasJoined: false
    )

    static let previewJoined = SeasonalEvent(
        eventId: "summer-reading-2026",
        title: "Summer Reading Challenge",
        description: "Read 20 chapters this July and earn the Summer Scholar badge.",
        startsAt: "2026-07-01T00:00:00Z",
        endsAt: "2026-07-31T23:59:59Z",
        targetChapters: 20,
        dailyTarget: 1,
        badge: BadgeItem(
            badgeId: "summer-scholar",
            name: "Summer Scholar",
            description: "Completed the Summer 2026 reading challenge.",
            category: "seasonal",
            isEarned: false,
            earnedAt: nil,
            icon: "☀️"
        ),
        bonusIp: 500,
        isActive: true,
        hasJoined: true
    )
}

extension EventProgress {
    static let previewInProgress = EventProgress(
        eventId: "summer-reading-2026",
        chaptersCompleted: 7,
        dailyChaptersCompleted: 1,
        isCompleted: false,
        joinedAt: "2026-07-03T08:00:00Z",
        completedAt: nil
    )

    static let previewCompleted = EventProgress(
        eventId: "summer-reading-2026",
        chaptersCompleted: 20,
        dailyChaptersCompleted: 2,
        isCompleted: true,
        joinedAt: "2026-07-01T10:00:00Z",
        completedAt: "2026-07-28T15:30:00Z"
    )
}

// MARK: - Preview SeasonalEventRepository

extension SeasonalEventRepository {
    /// Active event, user has NOT yet joined.
    static var previewNotJoined: SeasonalEventRepository {
        makeEventPreview(event: .preview, progress: nil)
    }

    /// Active event, user joined and in progress.
    static var previewInProgress: SeasonalEventRepository {
        makeEventPreview(event: .previewJoined, progress: .previewInProgress)
    }

    /// Active event, user completed the challenge.
    static var previewCompleted: SeasonalEventRepository {
        let completedEvent = SeasonalEvent(
            eventId: SeasonalEvent.previewJoined.eventId,
            title: SeasonalEvent.previewJoined.title,
            description: SeasonalEvent.previewJoined.description,
            startsAt: SeasonalEvent.previewJoined.startsAt,
            endsAt: SeasonalEvent.previewJoined.endsAt,
            targetChapters: SeasonalEvent.previewJoined.targetChapters,
            dailyTarget: SeasonalEvent.previewJoined.dailyTarget,
            badge: BadgeItem(
                badgeId: "summer-scholar",
                name: "Summer Scholar",
                description: "Completed the Summer 2026 reading challenge.",
                category: "seasonal",
                isEarned: true,
                earnedAt: "2026-07-28T15:30:00Z",
                icon: "☀️"
            ),
            bonusIp: SeasonalEvent.previewJoined.bonusIp,
            isActive: SeasonalEvent.previewJoined.isActive,
            hasJoined: SeasonalEvent.previewJoined.hasJoined
        )
        return makeEventPreview(event: completedEvent, progress: .previewCompleted)
    }

    /// No active event.
    static var previewNoEvent: SeasonalEventRepository {
        makeEventPreview(event: nil, progress: nil)
    }

    private static func makeEventPreview(
        event: SeasonalEvent?,
        progress: EventProgress?
    ) -> SeasonalEventRepository {
        let client = PreviewAPIClient { endpoint in
            switch endpoint.path {
            case "/book/events/active":
                return try JSONCoding.encoder.encode(ActiveEventResponse(event: event))
            case let p where p.hasSuffix("/join"):
                let joined = event.map { ev in
                    SeasonalEvent(
                        eventId: ev.eventId,
                        title: ev.title,
                        description: ev.description,
                        startsAt: ev.startsAt,
                        endsAt: ev.endsAt,
                        targetChapters: ev.targetChapters,
                        dailyTarget: ev.dailyTarget,
                        badge: ev.badge,
                        bonusIp: ev.bonusIp,
                        isActive: ev.isActive,
                        hasJoined: true
                    )
                }
                let initProgress = EventProgress(
                    eventId: event?.eventId ?? "",
                    chaptersCompleted: 0,
                    dailyChaptersCompleted: 0,
                    isCompleted: false,
                    joinedAt: "2026-07-03T10:00:00Z",
                    completedAt: nil
                )
                return try JSONCoding.encoder.encode(JoinEventResponse(event: joined, progress: initProgress))
            case let p where p.hasSuffix("/progress"):
                let prog = progress ?? EventProgress(
                    eventId: event?.eventId ?? "",
                    chaptersCompleted: 0,
                    dailyChaptersCompleted: 0,
                    isCompleted: false,
                    joinedAt: nil,
                    completedAt: nil
                )
                return try JSONCoding.encoder.encode(EventProgressResponse(progress: prog))
            default:
                throw AppError.notFound
            }
        }
        return SeasonalEventRepository(apiClient: client)
    }
}

// MARK: - Preview SeasonalEventModel

extension SeasonalEventModel {
    @MainActor static var previewNotJoined: SeasonalEventModel {
        SeasonalEventModel(
            repository: .previewNotJoined,
            celebrationPresenter: CelebrationPresenter()
        )
    }

    @MainActor static var previewInProgress: SeasonalEventModel {
        SeasonalEventModel(
            repository: .previewInProgress,
            celebrationPresenter: CelebrationPresenter()
        )
    }

    @MainActor static var previewCompleted: SeasonalEventModel {
        SeasonalEventModel(
            repository: .previewCompleted,
            celebrationPresenter: CelebrationPresenter()
        )
    }

    @MainActor static var previewNoEvent: SeasonalEventModel {
        SeasonalEventModel(
            repository: .previewNoEvent,
            celebrationPresenter: CelebrationPresenter()
        )
    }
}
