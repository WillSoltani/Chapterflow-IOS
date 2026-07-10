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

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // Only `eventId` is required; the deployed event definitions may omit any
    // display/target field, and `hasJoined` is inferred from an attached
    // `participation` object when the boolean is absent.

    private enum WireKeys: String, CodingKey {
        case eventId, title, description, startsAt, endsAt
        case targetChapters, dailyTarget, badge, bonusIp
        case isActive, hasJoined, participation
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        eventId = try c.decodeRequiredFirst(String.self, keys: [.eventId])
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        description = c.decodeFirst(String.self, keys: [.description])
        startsAt = c.decodeFirst(String.self, keys: [.startsAt]) ?? ""
        endsAt = c.decodeFirst(String.self, keys: [.endsAt]) ?? ""
        targetChapters = c.decodeFirst(Int.self, keys: [.targetChapters]) ?? 0
        dailyTarget = c.decodeFirst(Int.self, keys: [.dailyTarget]) ?? 0
        badge = c.decodeFirst(BadgeItem.self, keys: [.badge])
        bonusIp = c.decodeFirst(Int.self, keys: [.bonusIp]) ?? 0
        // `true` is correct for the only feed that serves these
        // (/book/events/active returns active events by construction);
        // joining is server-validated, so this cannot grant anything.
        isActive = c.decodeFirst(Bool.self, keys: [.isActive]) ?? true
        if let joined = c.decodeFirst(Bool.self, keys: [.hasJoined]) {
            hasJoined = joined
        } else {
            // Deployed /book/events/active attaches the user's participation
            // record to each event when they have joined.
            hasJoined = (try? c.nestedContainer(keyedBy: WireKeys.self, forKey: .participation)) != nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(eventId, forKey: .eventId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(targetChapters, forKey: .targetChapters)
        try c.encode(dailyTarget, forKey: .dailyTarget)
        try c.encodeIfPresent(badge, forKey: .badge)
        try c.encode(bonusIp, forKey: .bonusIp)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(hasJoined, forKey: .hasJoined)
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
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route returns `{events: […]}` (a list); the canonical shape
/// is `{event: {…}|null}`. Both decode — the list form surfaces its first
/// event. Encoding stays canonical.
public struct ActiveEventResponse: Codable, Sendable {
    public let event: SeasonalEvent?

    public init(event: SeasonalEvent?) {
        self.event = event
    }

    private enum CodingKeys: String, CodingKey { case event, events }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let single = container.decodeFirst(SeasonalEvent.self, keys: [.event]) {
            self.event = single
        } else if container.contains(.events) {
            let list = (try? container.decodeLossy(SeasonalEvent.self, forKey: .events)) ?? []
            self.event = list.first
        } else {
            self.event = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(event, forKey: .event)
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
