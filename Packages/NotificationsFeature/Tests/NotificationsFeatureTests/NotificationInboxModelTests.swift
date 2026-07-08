import Testing
import Foundation
@testable import NotificationsFeature
import Models

private let sampleNotifications: [AppNotification] = [
    AppNotification(
        notificationId: "n1",
        type: .badgeEarned,
        title: "Badge!",
        body: "You earned a badge.",
        isRead: false,
        createdAt: "2024-01-16T10:00:00Z"
    ),
    AppNotification(
        notificationId: "n2",
        type: .reviewDue,
        title: "Review",
        body: "Cards ready.",
        isRead: true,
        createdAt: "2024-01-15T08:00:00Z"
    ),
]

@Suite("NotificationInboxModel — fetch")
struct NotificationInboxModelFetchTests {

    @Test("fetch() populates notifications and unreadCount")
    @MainActor
    func fetchPopulatesState() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 1
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        #expect(model.notifications.count == 2)
        #expect(model.unreadCount == 1)
        #expect(model.isOffline == false)
        #expect(model.error == nil)
    }

    @Test("fetch() sets error when repo throws and inbox is empty")
    @MainActor
    func fetchSetsErrorOnEmptyInbox() async {
        let repo = FakeNotificationInboxRepository(notifications: [], unreadCount: 0)
        repo.shouldThrow = true
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        #expect(model.notifications.isEmpty)
        #expect(model.error != nil)
    }

    @Test("fetch() sets isOffline when repo throws but model already has data")
    @MainActor
    func fetchSetsOfflineWhenCached() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 1
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        #expect(model.notifications.count == 2)

        repo.shouldThrow = true
        await model.fetch()
        #expect(model.notifications.count == 2)
        #expect(model.isOffline == true)
    }
}

@Suite("NotificationInboxModel — mark all read")
struct NotificationInboxModelMarkAllReadTests {

    @Test("markAllRead() sets all isRead=true and unreadCount=0")
    @MainActor
    func markAllReadOptimistic() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 1
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        #expect(model.unreadCount == 1)

        await model.markAllRead()
        #expect(model.unreadCount == 0)
        #expect(model.notifications.allSatisfy { $0.isRead })
        #expect(repo.markAllReadCallCount == 1)
    }

    @Test("markAllRead() rolls back on server error")
    @MainActor
    func markAllReadRollsBackOnError() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 1
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        let previousUnread = model.unreadCount

        repo.shouldThrow = true
        await model.markAllRead()

        #expect(model.unreadCount == previousUnread)
        #expect(model.error != nil)
    }

    @Test("markAllRead() is a no-op when unreadCount is 0")
    @MainActor
    func markAllReadNoOpWhenAllRead() async {
        let allRead = sampleNotifications.map {
            AppNotification(
                notificationId: $0.notificationId,
                type: $0.type,
                title: $0.title,
                body: $0.body,
                isRead: true,
                createdAt: $0.createdAt
            )
        }
        let repo = FakeNotificationInboxRepository(notifications: allRead, unreadCount: 0)
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        await model.markAllRead()
        #expect(repo.markAllReadCallCount == 0)
    }
}

@Suite("NotificationInboxModel — badge count")
struct NotificationInboxModelBadgeTests {

    @Test("unreadCount reflects server value after fetch")
    @MainActor
    func unreadCountReflectsServer() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 7
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        #expect(model.unreadCount == 7)
    }

    @Test("unreadCount is 0 after markAllRead succeeds")
    @MainActor
    func unreadCountClearedAfterMarkAll() async {
        let repo = FakeNotificationInboxRepository(
            notifications: sampleNotifications,
            unreadCount: 1
        )
        let model = NotificationInboxModel(repository: repo)
        await model.fetch()
        await model.markAllRead()
        #expect(model.unreadCount == 0)
    }
}
