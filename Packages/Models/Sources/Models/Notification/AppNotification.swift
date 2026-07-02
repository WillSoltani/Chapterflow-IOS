/// An in-app notification from the notification inbox.
///
/// Returned within `GET /book/me/notifications`.
public struct AppNotification: Codable, Sendable, Identifiable {
    public let notificationId: String
    public let type: String
    public let title: String
    public let body: String
    public let isRead: Bool
    public let createdAt: String
    public let deepLink: String?

    public var id: String { notificationId }
}

public struct NotificationsResponse: Codable, Sendable {
    public let notifications: [AppNotification]
    public let unreadCount: Int
}
