import Foundation
import Models
import UserNotifications
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "review-notifications")

// MARK: - ReviewNotificationScheduler

/// Cancels legacy local `UNUserNotificationCenter` notifications for FSRS
/// review sessions at an irreversible session boundary.
///
/// Runs on the main actor so all `UNUserNotificationCenter` calls happen on the
/// same isolation domain as the framework type itself.
///
/// New scheduling is disabled until notification requests have an
/// account-scoped owner. The scheduling implementation is retained for a later
/// migration, but production repositories do not invoke it.
@MainActor
public final class ReviewNotificationScheduler {

    /// Process-global cleanup owner for legacy review notifications.
    public static let shared = ReviewNotificationScheduler()

    private init() {}

    /// Notification category identifier used for all review notifications.
    static let categoryId = "com.chapterflow.reviews.due"
    /// Thread identifier groups all review notifications in Notification Center.
    static let threadId   = "com.chapterflow.reviews"

    // MARK: - Schedule

    /// Schedules one notification for the next batch of due cards.
    ///
    /// - Only fires when the user has already granted `.alert` / `.badge` permission.
    /// - Cancels any previously scheduled review notifications before adding new ones
    ///   to avoid stale alerts.
    /// - A maximum of one future notification is scheduled (the soonest upcoming due date).
    public func scheduleNotifications(for cards: [FsrsCard]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Remove stale review notifications
        center.removePendingNotificationRequests(
            withIdentifiers: pendingIdentifiers(from: cards)
        )

        // Find the soonest future due date
        let now = Date()
        let futureDue = cards
            .compactMap { $0.dueDate }
            .filter { $0 > now }
            .sorted()
            .first

        guard let nextDue = futureDue else { return }

        let content = UNMutableNotificationContent()
        content.title = "Review time"
        content.body  = nextBatchBody(cards: cards, dueDate: nextDue)
        content.sound = .default
        content.threadIdentifier = Self.threadId
        content.categoryIdentifier = Self.categoryId
        content.interruptionLevel = .passive

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: nextDue
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "review-due-\(Int(nextDue.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            log.info("Scheduled review notification for \(nextDue.formatted())")
        } catch {
            log.warning("Failed to schedule review notification: \(error)")
        }
    }

    /// Cancels all pending and delivered review notifications.
    ///
    /// Delivered entries are account-private presentation too: leaving A's
    /// "cards due" copy in Notification Center after B becomes active would
    /// cross the session boundary even though no future request can fire.
    public func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending
            .filter { $0.identifier.hasPrefix("review-due-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered
            .filter { $0.request.identifier.hasPrefix("review-due-") }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    // MARK: - Private helpers

    private func pendingIdentifiers(from cards: [FsrsCard]) -> [String] {
        cards.compactMap { card in
            card.dueDate.map { "review-due-\(Int($0.timeIntervalSince1970))" }
        }
    }

    private func nextBatchBody(cards: [FsrsCard], dueDate: Date) -> String {
        let dueCount = cards.filter { card in
            guard let due = card.dueDate else { return false }
            return due <= dueDate.addingTimeInterval(86400)
        }.count

        if dueCount == 1 {
            return "You have 1 card due for review."
        }
        return "You have \(dueCount) cards due for review."
    }
}
