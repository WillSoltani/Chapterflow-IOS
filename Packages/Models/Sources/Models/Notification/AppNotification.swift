/// The kind of an in-app notification.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views should handle `.unknown` with a generic icon/action.
public enum NotificationKind: Sendable, Equatable, Hashable {
    case quizUnlocked
    case streakReminder
    case badgeEarned
    case reviewDue
    /// A notification kind the client does not recognise. Show generically; never crash.
    case unknown(String)
}

extension NotificationKind: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .quizUnlocked:   return "quiz_unlocked"
        case .streakReminder: return "streak_reminder"
        case .badgeEarned:    return "badge_earned"
        case .reviewDue:      return "review_due"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "quiz_unlocked":   self = .quizUnlocked
        case "streak_reminder": self = .streakReminder
        case "badge_earned":    self = .badgeEarned
        case "review_due":      self = .reviewDue
        default:                self = .unknown(rawValue)
        }
    }
}

extension NotificationKind: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = NotificationKind(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension NotificationKind: CaseIterable {
    public static var allCases: [NotificationKind] {
        [.quizUnlocked, .streakReminder, .badgeEarned, .reviewDue]
    }
}

// MARK: - AppNotification

/// An in-app notification from the notification inbox.
///
/// Returned within `GET /book/me/notifications`.
public struct AppNotification: Codable, Sendable, Identifiable {
    public let notificationId: String
    public let type: NotificationKind
    public let title: String
    public let body: String
    public let isRead: Bool
    public let createdAt: String
    public let deepLink: String?

    public var id: String { notificationId }

    public init(
        notificationId: String,
        type: NotificationKind,
        title: String,
        body: String,
        isRead: Bool,
        createdAt: String,
        deepLink: String? = nil
    ) {
        self.notificationId = notificationId
        self.type = type
        self.title = title
        self.body = body
        self.isRead = isRead
        self.createdAt = createdAt
        self.deepLink = deepLink
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // The deployed inbox items carry `readAt: string|null` instead of a
    // boolean `isRead` — without this mapping every entry fails decode and
    // the inbox silently renders empty.

    private enum WireKeys: String, CodingKey {
        case notificationId, type, title, body
        case isRead, readAt, createdAt, deepLink
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        notificationId = try c.decodeRequiredFirst(String.self, keys: [.notificationId])
        type = c.decodeFirst(NotificationKind.self, keys: [.type]) ?? .unknown("")
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        body = c.decodeFirst(String.self, keys: [.body]) ?? ""
        if let flag = c.decodeFirst(Bool.self, keys: [.isRead]) {
            isRead = flag
        } else {
            isRead = c.decodeFirst(String.self, keys: [.readAt]) != nil
        }
        createdAt = c.decodeFirst(String.self, keys: [.createdAt]) ?? ""
        deepLink = c.decodeFirst(String.self, keys: [.deepLink])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(notificationId, forKey: .notificationId)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(isRead, forKey: .isRead)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(deepLink, forKey: .deepLink)
    }
}

// MARK: - NotificationsResponse

/// Response from `GET /book/me/notifications`.
/// Decodes the `notifications` array lossily — one malformed notification is
/// dropped and logged while the rest of the inbox survives.
public struct NotificationsResponse: Codable, Sendable {
    public let notifications: [AppNotification]
    public let unreadCount: Int

    private enum CodingKeys: String, CodingKey { case notifications, unreadCount }

    public init(notifications: [AppNotification], unreadCount: Int) {
        self.notifications = notifications
        self.unreadCount = unreadCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.notifications = try container.decodeLossy(AppNotification.self, forKey: .notifications)
        self.unreadCount = try container.decode(Int.self, forKey: .unreadCount)
    }
}
