import Foundation

// MARK: - NotificationPreferences

/// The server-side notification preference block from `GET /book/me/settings`.
///
/// All fields are optional so the client gracefully handles servers that
/// haven't yet added a new field (RF2 forward compatibility).
public struct NotificationPreferences: Codable, Sendable, Equatable {

    // MARK: - Sub-types

    public struct Channels: Codable, Sendable, Equatable {
        public var push: Bool
        public var email: Bool

        public init(push: Bool = true, email: Bool = true) {
            self.push = push
            self.email = email
        }
    }

    // MARK: - Properties

    public var channels: Channels
    public var readingReminderEnabled: Bool
    /// 24-hour "HH:MM" local time string, e.g. `"20:00"`.
    public var readingReminderTime: String
    public var streakReminderEnabled: Bool
    public var reviewReminderEnabled: Bool
    public var badgeAlertsEnabled: Bool
    public var weeklyDigestEnabled: Bool
    /// When true, no notifications are delivered between `quietHoursStart` and `quietHoursEnd`.
    public var quietHoursEnabled: Bool
    /// 24-hour "HH:MM" local time — quiet period begins at this time (inclusive).
    public var quietHoursStart: String
    /// 24-hour "HH:MM" local time — quiet period ends at this time (exclusive).
    /// May be earlier than `quietHoursStart` to span midnight (e.g. 22:00 → 08:00).
    public var quietHoursEnd: String

    // MARK: - Init

    public init(
        channels: Channels = Channels(),
        readingReminderEnabled: Bool = true,
        readingReminderTime: String = "20:00",
        streakReminderEnabled: Bool = true,
        reviewReminderEnabled: Bool = true,
        badgeAlertsEnabled: Bool = true,
        weeklyDigestEnabled: Bool = false,
        quietHoursEnabled: Bool = false,
        quietHoursStart: String = "22:00",
        quietHoursEnd: String = "08:00"
    ) {
        self.channels = channels
        self.readingReminderEnabled = readingReminderEnabled
        self.readingReminderTime = readingReminderTime
        self.streakReminderEnabled = streakReminderEnabled
        self.reviewReminderEnabled = reviewReminderEnabled
        self.badgeAlertsEnabled = badgeAlertsEnabled
        self.weeklyDigestEnabled = weeklyDigestEnabled
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
    }

    public static let `default` = NotificationPreferences()

    // MARK: - Codable (lenient: absent fields fall back to defaults)

    private enum CodingKeys: String, CodingKey {
        case channels
        case readingReminderEnabled
        case readingReminderTime
        case streakReminderEnabled
        case reviewReminderEnabled
        case badgeAlertsEnabled
        case weeklyDigestEnabled
        case quietHoursEnabled
        case quietHoursStart
        case quietHoursEnd
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channels               = try container.decodeIfPresent(Channels.self, forKey: .channels) ?? Channels()
        readingReminderEnabled = try container.decodeIfPresent(Bool.self,   forKey: .readingReminderEnabled) ?? true
        readingReminderTime    = try container.decodeIfPresent(String.self, forKey: .readingReminderTime)    ?? "20:00"
        streakReminderEnabled  = try container.decodeIfPresent(Bool.self,   forKey: .streakReminderEnabled)  ?? true
        reviewReminderEnabled  = try container.decodeIfPresent(Bool.self,   forKey: .reviewReminderEnabled)  ?? true
        badgeAlertsEnabled     = try container.decodeIfPresent(Bool.self,   forKey: .badgeAlertsEnabled)     ?? true
        weeklyDigestEnabled    = try container.decodeIfPresent(Bool.self,   forKey: .weeklyDigestEnabled)    ?? false
        quietHoursEnabled      = try container.decodeIfPresent(Bool.self,   forKey: .quietHoursEnabled)      ?? false
        quietHoursStart        = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)        ?? "22:00"
        quietHoursEnd          = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)          ?? "08:00"
    }
}

// MARK: - UserSettingsResponse (envelope for GET /book/me/settings)

/// Lenient wrapper around the full settings response. Only the `notifications`
/// key is needed here; all other fields are ignored by default `Codable` synthesis.
struct UserSettingsResponse: Decodable, Sendable {
    let notifications: NotificationPreferences?
}

// MARK: - NotificationSettingsUpdate (body for PATCH /book/me/settings)

/// The PATCH body sent to `/book/me/settings` when notification preferences change.
struct NotificationSettingsUpdate: Encodable, Sendable {
    struct NotificationsBlock: Encodable, Sendable {
        struct ChannelsBlock: Encodable, Sendable {
            let push: Bool
            let email: Bool
        }
        let channels: ChannelsBlock
        let readingReminderEnabled: Bool
        let readingReminderTime: String
        let streakReminderEnabled: Bool
        let reviewReminderEnabled: Bool
        let badgeAlertsEnabled: Bool
        let weeklyDigestEnabled: Bool
        let quietHoursEnabled: Bool
        let quietHoursStart: String
        let quietHoursEnd: String
    }
    let notifications: NotificationsBlock

    init(from prefs: NotificationPreferences) {
        notifications = NotificationsBlock(
            channels: .init(push: prefs.channels.push, email: prefs.channels.email),
            readingReminderEnabled: prefs.readingReminderEnabled,
            readingReminderTime: prefs.readingReminderTime,
            streakReminderEnabled: prefs.streakReminderEnabled,
            reviewReminderEnabled: prefs.reviewReminderEnabled,
            badgeAlertsEnabled: prefs.badgeAlertsEnabled,
            weeklyDigestEnabled: prefs.weeklyDigestEnabled,
            quietHoursEnabled: prefs.quietHoursEnabled,
            quietHoursStart: prefs.quietHoursStart,
            quietHoursEnd: prefs.quietHoursEnd
        )
    }
}
