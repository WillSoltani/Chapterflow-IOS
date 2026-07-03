import Foundation

// MARK: - SeasonalEvent

/// A time-limited event that challenges users to complete chapters for bonus rewards.
///
/// Returned by `GET /book/events/active`.
/// The `event` key in `ActiveEventResponse` is `nil` when no event is running.
public struct SeasonalEvent: Codable, Sendable, Identifiable {
    public let eventId: String
    public let title: String
    public let description: String?
    /// ISO-8601 timestamp when the event begins.
    public let startsAt: String
    /// ISO-8601 timestamp when the event ends.
    public let endsAt: String
    /// Total chapters the user must complete to finish the event.
    public let targetChapters: Int
    /// Suggested chapters per day to finish on time.
    public let dailyTarget: Int
    /// The badge awarded on event completion.
    public let badge: BadgeItem?
    /// Bonus flow-points (impact points) awarded on completion.
    public let bonusIp: Int
    /// Whether the event window is currently open.
    public let isActive: Bool
    /// Whether the signed-in user has already joined this event.
    public let hasJoined: Bool

    public var id: String { eventId }

    public init(
        eventId: String,
        title: String,
        description: String?,
        startsAt: String,
        endsAt: String,
        targetChapters: Int,
        dailyTarget: Int,
        badge: BadgeItem?,
        bonusIp: Int,
        isActive: Bool,
        hasJoined: Bool
    ) {
        self.eventId = eventId
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.targetChapters = targetChapters
        self.dailyTarget = dailyTarget
        self.badge = badge
        self.bonusIp = bonusIp
        self.isActive = isActive
        self.hasJoined = hasJoined
    }
}

// MARK: - EventProgress

/// The authenticated user's progress in a seasonal event.
///
/// Returned by `GET|POST /book/me/events/{id}/progress`.
public struct EventProgress: Codable, Sendable {
    public let eventId: String
    /// Chapters completed since joining this event.
    public let chaptersCompleted: Int
    /// Chapters completed today within this event.
    public let dailyChaptersCompleted: Int
    /// Whether the user has satisfied the event's chapter target.
    public let isCompleted: Bool
    /// ISO-8601 timestamp when the user joined, or `nil` if not yet joined.
    public let joinedAt: String?
    /// ISO-8601 timestamp when the event was completed, or `nil` if not yet.
    public let completedAt: String?

    public init(
        eventId: String,
        chaptersCompleted: Int,
        dailyChaptersCompleted: Int,
        isCompleted: Bool,
        joinedAt: String?,
        completedAt: String?
    ) {
        self.eventId = eventId
        self.chaptersCompleted = chaptersCompleted
        self.dailyChaptersCompleted = dailyChaptersCompleted
        self.isCompleted = isCompleted
        self.joinedAt = joinedAt
        self.completedAt = completedAt
    }
}

// MARK: - Response wrappers

/// Wraps `GET /book/events/active`.
/// The `event` key is `nil` when no event is currently running.
public struct ActiveEventResponse: Codable, Sendable {
    public let event: SeasonalEvent?

    public init(event: SeasonalEvent?) {
        self.event = event
    }
}

/// Wraps `GET|POST /book/me/events/{id}/progress`.
public struct EventProgressResponse: Codable, Sendable {
    public let progress: EventProgress

    public init(progress: EventProgress) {
        self.progress = progress
    }
}

/// Wraps `POST /book/me/events/{id}/join`.
public struct JoinEventResponse: Codable, Sendable {
    public let event: SeasonalEvent?
    public let progress: EventProgress?

    public init(event: SeasonalEvent?, progress: EventProgress?) {
        self.event = event
        self.progress = progress
    }
}
