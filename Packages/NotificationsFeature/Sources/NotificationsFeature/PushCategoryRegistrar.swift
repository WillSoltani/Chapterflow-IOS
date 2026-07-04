import Foundation

#if canImport(UIKit)
import UserNotifications

/// Registers all UNNotificationCategory objects with the system at app launch.
///
/// Call `PushCategoryRegistrar.registerCategories()` once, early in the app lifecycle
/// (before any notification can be delivered). Category registration is idempotent
/// and does NOT require the user to have granted notification permission.
///
/// Categories define the actionable buttons shown in banners and the notification
/// expanded view. P9.6's Notification Service Extension attaches to notifications
/// whose aps payload sets `"mutable-content": 1`; categories are independent of that.
public enum PushCategoryRegistrar {

    // MARK: - Public entry point

    /// Registers all ChapterFlow push categories with `UNUserNotificationCenter`.
    /// Safe to call multiple times — the system replaces the previous set.
    public static func registerCategories() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(allCategories)
    }

    // MARK: - Category set

    static var allCategories: Set<UNNotificationCategory> {
        Set(PushNotificationType.known.map(category(for:)) + [generalCategory])
    }

    // MARK: - Per-type category builders

    private static func category(for type: PushNotificationType) -> UNNotificationCategory {
        switch type {
        case .badgeEarned:
            return makeCategory(type, actions: [viewBadgeAction], options: [.customDismissAction])
        case .tierUp:
            return makeCategory(type, actions: [viewProgressAction], options: [.customDismissAction])
        case .streakMilestone:
            return makeCategory(type, actions: [viewProgressAction], options: [.customDismissAction])
        case .insightSpark:
            return makeCategory(type, actions: [openChapterAction])
        case .readingReminder:
            return makeCategory(type, actions: [openChapterAction])
        case .streakAtRisk:
            return makeCategory(type, actions: [readNowAction])
        case .partnerNudge:
            return makeCategory(type, actions: [])
        case .commitmentFollowup:
            return makeCategory(type, actions: [openChapterAction])
        case .eventReminder:
            return makeCategory(type, actions: [])
        case .scenarioApproved:
            return makeCategory(type, actions: [viewProgressAction])
        case .scenarioRejected:
            return makeCategory(type, actions: [viewProgressAction])
        case .unknown:
            return generalCategory
        }
    }

    private static func makeCategory(
        _ type: PushNotificationType,
        actions: [UNNotificationAction],
        options: UNNotificationCategoryOptions = []
    ) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: type.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: options
        )
    }

    // MARK: - Fallback category

    private static var generalCategory: UNNotificationCategory {
        UNNotificationCategory(identifier: "CF_GENERAL", actions: [], intentIdentifiers: [], options: [])
    }

    // MARK: - Shared actions

    private static var openChapterAction: UNNotificationAction {
        UNNotificationAction(identifier: PushActionIdentifier.openChapter, title: "Open Chapter", options: [.foreground])
    }

    private static var readNowAction: UNNotificationAction {
        UNNotificationAction(identifier: PushActionIdentifier.openChapter, title: "Read Now", options: [.foreground])
    }

    private static var viewBadgeAction: UNNotificationAction {
        UNNotificationAction(identifier: PushActionIdentifier.viewBadge, title: "View Badge", options: [.foreground])
    }

    private static var viewProgressAction: UNNotificationAction {
        UNNotificationAction(identifier: PushActionIdentifier.viewProgress, title: "View Progress", options: [.foreground])
    }
}
#endif
