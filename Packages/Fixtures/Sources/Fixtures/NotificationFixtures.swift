import Models

extension Fixtures {

    // MARK: - Notifications

    /// In-app notification inbox: 4 notifications, 2 unread.
    /// Covers types: quiz_unlocked, streak_reminder, badge_earned, review_due.
    public static let notificationsResponse: NotificationsResponse = load("notifications")

    /// Convenience accessor.
    public static var notifications: [AppNotification] { notificationsResponse.notifications }

    /// Unread notifications.
    public static var unreadNotifications: [AppNotification] { notifications.filter { !$0.isRead } }
}
