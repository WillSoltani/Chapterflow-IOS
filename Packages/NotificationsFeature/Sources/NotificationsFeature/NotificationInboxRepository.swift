import Foundation
import CoreKit
import Models
import Networking

// MARK: - Protocol

public protocol NotificationInboxRepository: Sendable {
    func fetchNotifications() async throws -> NotificationsResponse
    func markAllRead() async throws
}

// MARK: - Cache

/// UserDefaults-backed cache for the notification inbox.
/// Renders last-fetched data when the device is offline.
public struct NotificationInboxCache: @unchecked Sendable {
    private let defaults: UserDefaults
    private let defaultsKey: String

    public init(storageNamespace: String, defaults: UserDefaults = .standard) {
        precondition(!storageNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.defaults = defaults
        self.defaultsKey = "cf.notifications.inbox.v2.\(storageNamespace)"
    }

    func store(_ response: NotificationsResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    func load() -> NotificationsResponse? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(NotificationsResponse.self, from: data)
    }
}

// MARK: - Live

public struct LiveNotificationInboxRepository: NotificationInboxRepository {
    private let apiClient: any APIClientProtocol
    private let cache: NotificationInboxCache
    private let workPermit: SessionWorkPermit
    private let log = AppLog(category: .notifications)

    public init(
        apiClient: any APIClientProtocol,
        storageNamespace: String,
        defaults: UserDefaults = .standard,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.apiClient = apiClient
        self.cache = NotificationInboxCache(storageNamespace: storageNamespace, defaults: defaults)
        self.workPermit = workPermit
    }

    public func fetchNotifications() async throws -> NotificationsResponse {
        let ticket = try workPermit.begin()
        do {
            let response: NotificationsResponse = try await apiClient.send(Endpoints.getNotifications())
            try workPermit.commit(ticket) {
                cache.store(response)
            }
            log.info("Fetched \(response.notifications.count) notifications, \(response.unreadCount) unread")
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cached = cache.load() {
                log.info("Network error — returning cached inbox")
                return cached
            }
            throw error
        }
    }

    public func markAllRead() async throws {
        // Server returns 200 with an empty or minimal body; we discard it.
        struct IgnoredBody: Decodable, Sendable {}
        let _: IgnoredBody = try await apiClient.send(Endpoints.postMarkAllNotificationsRead())
        log.info("All notifications marked as read")
    }
}

// MARK: - Fake (tests + previews)

public final class FakeNotificationInboxRepository: NotificationInboxRepository, @unchecked Sendable {
    public var stubbedNotifications: [AppNotification]
    public var stubbedUnreadCount: Int
    public private(set) var markAllReadCallCount = 0
    public var shouldThrow: Bool = false

    public init(notifications: [AppNotification] = [], unreadCount: Int = 0) {
        self.stubbedNotifications = notifications
        self.stubbedUnreadCount = unreadCount
    }

    public func fetchNotifications() async throws -> NotificationsResponse {
        if shouldThrow { throw AppError.offline }
        return NotificationsResponse(notifications: stubbedNotifications, unreadCount: stubbedUnreadCount)
    }

    public func markAllRead() async throws {
        if shouldThrow { throw AppError.offline }
        markAllReadCallCount += 1
        stubbedNotifications = stubbedNotifications.map {
            AppNotification(
                notificationId: $0.notificationId,
                type: $0.type,
                title: $0.title,
                body: $0.body,
                isRead: true,
                createdAt: $0.createdAt,
                deepLink: $0.deepLink
            )
        }
        stubbedUnreadCount = 0
    }
}
