import Foundation
import Observation
import CoreKit
import Models

// MARK: - NotificationInboxModel

/// Observable model for the in-app notification inbox.
///
/// Owns a list of `AppNotification` items, the server-side unread count, and
/// loading/error state. Supports optimistic mark-all-read and offline rendering
/// from the repository's UserDefaults cache.
@Observable
@MainActor
public final class NotificationInboxModel {

    // MARK: - Published state

    /// The current inbox list, sorted newest-first.
    public private(set) var notifications: [AppNotification] = []

    /// Server-reported unread count; cleared to 0 after mark-all-read.
    public private(set) var unreadCount: Int = 0

    /// True while a network fetch is in flight.
    public private(set) var isLoading: Bool = false

    /// Set when a fetch or mark-all-read fails.
    public private(set) var error: AppError?

    /// True when the inbox is rendered from cache because the network is unavailable.
    public private(set) var isOffline: Bool = false

    // MARK: - Private

    private let repository: any NotificationInboxRepository

    // MARK: - Init

    public init(repository: any NotificationInboxRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Fetches the notification inbox, falling back to cached data on error.
    public func fetch() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await repository.fetchNotifications()
            notifications = response.notifications
            unreadCount = response.unreadCount
            isOffline = false
        } catch let appError as AppError {
            if notifications.isEmpty {
                error = appError
            }
            isOffline = !notifications.isEmpty
        } catch {
            if notifications.isEmpty {
                self.error = .offline
            }
            isOffline = !notifications.isEmpty
        }
    }

    /// Optimistically marks all notifications as read, then confirms with the server.
    /// Rolls back on failure.
    public func markAllRead() async {
        guard unreadCount > 0 else { return }

        // Optimistic update
        let previousNotifications = notifications
        let previousUnreadCount = unreadCount
        notifications = notifications.map {
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
        unreadCount = 0

        do {
            try await repository.markAllRead()
        } catch let appError as AppError {
            // Roll back on failure
            notifications = previousNotifications
            unreadCount = previousUnreadCount
            error = appError
        } catch {
            notifications = previousNotifications
            unreadCount = previousUnreadCount
            self.error = .offline
        }
    }

    // MARK: - Deep-link routing

    /// Returns the deep-link URL for a notification row tap.
    ///
    /// Prefers the server-supplied `deepLink` field. Falls back to a type-based
    /// default so unknown kinds still navigate somewhere sensible (RF2).
    /// `nonisolated` because this is pure computation with no actor state access.
    public nonisolated static func routingURL(for notification: AppNotification) -> URL? {
        if let raw = notification.deepLink,
           let url = URL(string: raw),
           url.scheme?.lowercased() == "chapterflow" {
            return url
        }
        return fallbackURL(for: notification.type)
    }

    private nonisolated static func fallbackURL(for kind: NotificationKind) -> URL? {
        switch kind {
        case .quizUnlocked:   return URL(string: "chapterflow://library")
        case .streakReminder: return URL(string: "chapterflow://engagement")
        case .badgeEarned:    return URL(string: "chapterflow://profile")
        case .reviewDue:      return URL(string: "chapterflow://review")
        case .unknown:        return URL(string: "chapterflow://engagement")
        }
    }
}
