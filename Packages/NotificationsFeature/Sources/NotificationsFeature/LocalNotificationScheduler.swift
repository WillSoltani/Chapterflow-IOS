import Foundation
@preconcurrency import UserNotifications
import Models
import CoreKit

// MARK: - Clock abstraction

/// Injectable clock so tests can assert on scheduling without touching wall time.
public protocol NotificationClock: Sendable {
    var now: Date { get }
}

public struct SystemNotificationClock: NotificationClock, Sendable {
    public init() {}
    public var now: Date { Date() }
}

/// A clock that returns a fixed, mutable date. `@unchecked Sendable` — mutate
/// only from the `@MainActor` test context.
public final class FixedNotificationClock: NotificationClock, @unchecked Sendable {
    public var now: Date
    public init(now: Date) { self.now = now }
}

// MARK: - Stable notification identifiers

/// Stable `UNNotificationRequest` identifiers used by `LocalNotificationScheduler`.
///
/// Using one identifier per kind means rescheduling replaces the prior request
/// instead of accumulating duplicates.
public enum LocalNotificationID {
    /// Daily reading reminder (repeating).
    public static let dailyReading   = "cf.local.daily-reading"
    /// Evening streak-at-risk reminder (one-shot, cancelled on reading).
    public static let streakAtRisk   = "cf.local.streak-at-risk"
    /// Next FSRS review batch due (one-shot, cancelled on session complete).
    public static let reviewDue      = "cf.local.review-due"
    /// Per-commitment follow-up. Stable across reschedules because it embeds the server ID.
    public static func commitment(_ id: String) -> String { "cf.local.commitment.\(id)" }
    /// Set of all non-commitment identifiers for bulk operations.
    public static let fixed: Set<String> = [dailyReading, streakAtRisk, reviewDue]
}

// MARK: - Scheduling input

/// All inputs the scheduler needs to decide what to schedule.
///
/// Pass fresh values on every reschedule call; the scheduler derives the full
/// pending set from scratch and replaces whatever was there before.
public struct LocalSchedulerInput: Sendable {
    /// Current notification preferences (from P9.2 settings).
    public let prefs: NotificationPreferences
    /// Locally cached FSRS cards with their due dates.
    public let cards: [FsrsCard]
    /// The user's active commitments.
    public let commitments: [Commitment]
    /// `true` when at least one reading session has completed today.
    public let readToday: Bool

    public init(
        prefs: NotificationPreferences,
        cards: [FsrsCard],
        commitments: [Commitment],
        readToday: Bool
    ) {
        self.prefs       = prefs
        self.cards       = cards
        self.commitments = commitments
        self.readToday   = readToday
    }
}

// MARK: - LocalNotificationScheduler

/// Central scheduler for all ChapterFlow local notifications.
///
/// Call `reschedule(input:)` whenever the user's state changes (prefs update,
/// reading session ends, reviews complete, new commitment created). Uses stable
/// per-kind identifiers so every reschedule is idempotent — no duplicates.
///
/// Quiet hours: when `prefs.quietHoursEnabled`, one-shot notifications whose
/// trigger falls within the quiet window are pushed to just after `quietHoursEnd`.
/// The repeating daily reading reminder is adjusted to the first available minute
/// outside the quiet window.
///
/// P9.7 (server-side quiet hours sync) will feed updated quiet-hours values into
/// `NotificationPreferences`; the scheduler reads them transparently.
@Observable
@MainActor
public final class LocalNotificationScheduler {

    // MARK: - Shared singleton

    public static let shared = LocalNotificationScheduler(coordinator: NotificationCoordinator.shared)

    // MARK: - Dependencies

    private let center: any NotificationSchedulingCenter
    private let clock: any NotificationClock
    private let coordinator: (any CoordinatorGate)?
    private let log = AppLog(category: .notifications)

    // MARK: - Init

    public init(
        center: any NotificationSchedulingCenter = SystemNotificationSchedulingCenter(),
        clock: any NotificationClock = SystemNotificationClock(),
        coordinator: (any CoordinatorGate)? = nil
    ) {
        self.center      = center
        self.clock       = clock
        self.coordinator = coordinator
    }

    // MARK: - Full reschedule

    /// Derives the complete set of local notifications from `input` and replaces
    /// any previously scheduled local notifications of the same kinds.
    ///
    /// Safe to call after every significant state change — it is idempotent.
    public func reschedule(input: LocalSchedulerInput) async {
        guard await center.isAuthorized() else {
            log.info("LocalNotificationScheduler: skipping — not authorized")
            return
        }

        let cal = Calendar.current
        let now = clock.now

        await scheduleReadingReminder(prefs: input.prefs, cal: cal)
        await scheduleStreakAtRisk(prefs: input.prefs, readToday: input.readToday, cal: cal, now: now)
        await scheduleReviewDue(prefs: input.prefs, cards: input.cards, cal: cal, now: now)
        await scheduleCommitments(prefs: input.prefs, commitments: input.commitments, cal: cal, now: now)
    }

    // MARK: - Targeted cancellations

    /// Cancel the streak-at-risk reminder (call when the user starts reading today).
    public func cancelAtRiskReminder() async {
        center.removeRequests(withIdentifiers: [LocalNotificationID.streakAtRisk])
        log.info("Cancelled streak-at-risk reminder")
    }

    /// Cancel the review-due reminder (call when the user completes their review session).
    public func cancelReviewReminder() async {
        center.removeRequests(withIdentifiers: [LocalNotificationID.reviewDue])
        log.info("Cancelled review-due reminder")
    }

    /// Cancel the follow-up reminder for a specific commitment (call on reflection submit).
    public func cancelCommitmentReminder(id: String) async {
        center.removeRequests(withIdentifiers: [LocalNotificationID.commitment(id)])
        log.info("Cancelled commitment reminder: \(id)")
    }

    /// Cancel all local notifications scheduled by this scheduler.
    public func cancelAll() async {
        let pending = await center.pendingRequests()
        let ours = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("cf.local.") }
        center.removeRequests(withIdentifiers: ours)
        log.info("Cancelled all local notifications (\(ours.count))")
    }

    // MARK: - Snooze

    /// Reschedule a pending notification with the same identifier at a new fire date.
    ///
    /// Bypasses the coordinator gate — snooze is a direct user action.
    public func snoozeRequest(
        identifier: String,
        content: UNNotificationContent,
        until fireDate: Date
    ) async {
        center.removeRequests(withIdentifiers: [identifier])
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.addRequest(request)
            log.info("Snoozed \(identifier) until \(fireDate.formatted())")
        } catch {
            log.warning("Snooze failed for \(identifier): \(error)")
        }
    }

    // MARK: - Coordinator-gated add helper

    /// Asks the coordinator whether to schedule, adds the request if permitted,
    /// then notifies the coordinator on success.
    private func gatedAdd(
        _ request: UNNotificationRequest,
        type: PushNotificationType,
        targetId: String?,
        prefs: NotificationPreferences
    ) async {
        let priority = type.coordinatorPriority
        if let gate = coordinator {
            let ok = await gate.shouldSchedule(
                type: type,
                targetId: targetId,
                prefs: prefs,
                priority: priority
            )
            guard ok else { return }
        }
        do {
            try await center.addRequest(request)
            await coordinator?.didSchedule(type: type, targetId: targetId)
        } catch {
            log.warning("Failed to schedule \(type.rawValue): \(error)")
        }
    }

    // MARK: - Reading reminder

    private func scheduleReadingReminder(
        prefs: NotificationPreferences,
        cal: Calendar
    ) async {
        guard prefs.readingReminderEnabled else {
            center.removeRequests(withIdentifiers: [LocalNotificationID.dailyReading])
            return
        }

        guard let (hour, minute) = parseHHMM(prefs.readingReminderTime) else {
            log.warning("Invalid readingReminderTime format: \(prefs.readingReminderTime)")
            return
        }

        // Adjust out of quiet hours if needed
        var (adjHour, adjMinute) = (hour, minute)
        if prefs.quietHoursEnabled,
           let qStart = parseHHMM(prefs.quietHoursStart),
           let qEnd   = parseHHMM(prefs.quietHoursEnd),
           isMinuteInQuietHours(hour * 60 + minute, start: qStart, end: qEnd) {
            (adjHour, adjMinute) = qEnd
            log.info("Reading reminder adjusted to \(adjHour):\(String(format: "%02d", adjMinute)) to clear quiet hours")
        }

        var comps = DateComponents()
        comps.hour   = adjHour
        comps.minute = adjMinute
        comps.second = 0

        let content = UNMutableNotificationContent()
        content.title = "Time to read"
        content.body  = "Keep your streak going — open a chapter now."
        content.sound = .default
        content.categoryIdentifier = PushNotificationType.readingReminder.categoryIdentifier
        content.threadIdentifier   = "cf.reading"
        content.interruptionLevel  = .passive

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: LocalNotificationID.dailyReading,
            content: content,
            trigger: trigger
        )

        await gatedAdd(request, type: .readingReminder, targetId: nil, prefs: prefs)
        log.info("Scheduled daily reading reminder at \(adjHour):\(String(format: "%02d", adjMinute))")
    }

    // MARK: - Streak-at-risk reminder

    private func scheduleStreakAtRisk(
        prefs: NotificationPreferences,
        readToday: Bool,
        cal: Calendar,
        now: Date
    ) async {
        guard prefs.streakReminderEnabled else {
            center.removeRequests(withIdentifiers: [LocalNotificationID.streakAtRisk])
            return
        }

        if readToday {
            center.removeRequests(withIdentifiers: [LocalNotificationID.streakAtRisk])
            return
        }

        // Fire at 20:00 local time today if that is still in the future; otherwise skip.
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour   = 20
        comps.minute = 0
        comps.second = 0

        guard var fireDate = cal.date(from: comps), fireDate > now else { return }

        fireDate = adjustForQuietHours(fireDate, prefs: prefs, cal: cal)

        let content = UNMutableNotificationContent()
        content.title = "Your streak is at risk"
        content.body  = "Read something today to keep your streak alive."
        content.sound = .default
        content.categoryIdentifier = PushNotificationType.streakAtRisk.categoryIdentifier
        content.threadIdentifier   = "cf.streak"
        content.interruptionLevel  = .timeSensitive

        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let request = UNNotificationRequest(
            identifier: LocalNotificationID.streakAtRisk,
            content: content,
            trigger: trigger
        )

        await gatedAdd(request, type: .streakAtRisk, targetId: nil, prefs: prefs)
        log.info("Scheduled streak-at-risk reminder for \(fireDate.formatted())")
    }

    // MARK: - Review-due reminder

    private func scheduleReviewDue(
        prefs: NotificationPreferences,
        cards: [FsrsCard],
        cal: Calendar,
        now: Date
    ) async {
        guard prefs.reviewReminderEnabled else {
            center.removeRequests(withIdentifiers: [LocalNotificationID.reviewDue])
            return
        }

        // Find the earliest future due date across all cards.
        let nextDue = cards
            .compactMap(\.dueDate)
            .filter { $0 > now }
            .min()

        guard var fireDate = nextDue else {
            // No upcoming due cards — cancel any existing reminder.
            center.removeRequests(withIdentifiers: [LocalNotificationID.reviewDue])
            return
        }

        fireDate = adjustForQuietHours(fireDate, prefs: prefs, cal: cal)

        let dueCount = cards.filter { card in
            guard let due = card.dueDate else { return card.state == .new }
            return due <= fireDate.addingTimeInterval(3600)   // cards due within 1hr of the reminder
        }.count

        let content = UNMutableNotificationContent()
        content.title = "Reviews waiting"
        content.body  = dueCount == 1
            ? "1 card is due for review."
            : "\(dueCount) cards are due for review."
        content.sound = .default
        content.categoryIdentifier = PushNotificationType.reviewDue.categoryIdentifier
        content.threadIdentifier   = "cf.reviews"
        content.interruptionLevel  = .passive
        content.userInfo           = ["type": PushNotificationType.reviewDue.rawValue]

        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let request = UNNotificationRequest(
            identifier: LocalNotificationID.reviewDue,
            content: content,
            trigger: trigger
        )

        await gatedAdd(request, type: .reviewDue, targetId: nil, prefs: prefs)
        log.info("Scheduled review-due reminder for \(fireDate.formatted()) (\(dueCount) cards)")
    }

    // MARK: - Commitment follow-up reminders

    private func scheduleCommitments(
        prefs: NotificationPreferences,
        commitments: [Commitment],
        cal: Calendar,
        now: Date
    ) async {
        // Cancel reminders for commitments that are no longer active.
        let activeIds = Set(commitments.filter { $0.status == .active }.map(\.id))
        let pending = await center.pendingRequests()
        let staleCommitmentIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("cf.local.commitment.") }
            .filter { id in
                let cid = String(id.dropFirst("cf.local.commitment.".count))
                return !activeIds.contains(cid)
            }
        if !staleCommitmentIds.isEmpty {
            center.removeRequests(withIdentifiers: staleCommitmentIds)
        }

        // Schedule each active commitment whose follow-up is in the future.
        for commitment in commitments where commitment.status == .active {
            guard commitment.followUpDate > now else { continue }

            let fireDate = adjustForQuietHours(commitment.followUpDate, prefs: prefs, cal: cal)

            let content = UNMutableNotificationContent()
            content.title = "Commitment check-in"
            content.body  = "If \(commitment.ifStatement) — how did it go?"
            content.sound = .default
            content.categoryIdentifier = PushNotificationType.commitmentFollowup.categoryIdentifier
            content.threadIdentifier   = "cf.commitments"
            content.interruptionLevel  = .passive
            content.userInfo           = [
                "type": "commitment_followup",
                "commitmentId": commitment.id
            ]

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: LocalNotificationID.commitment(commitment.id),
                content: content,
                trigger: trigger
            )

            await gatedAdd(
                request,
                type: .commitmentFollowup,
                targetId: commitment.id,
                prefs: prefs
            )
            log.info("Scheduled commitment reminder for \(commitment.id) at \(fireDate.formatted())")
        }
    }

    // MARK: - Quiet hours helpers

    /// Pushes `date` to just after `quietHoursEnd` when it falls in the quiet window.
    /// Returns `date` unchanged when quiet hours are disabled or the date is clear.
    func adjustForQuietHours(_ date: Date, prefs: NotificationPreferences, cal: Calendar) -> Date {
        guard prefs.quietHoursEnabled,
              let qStart = parseHHMM(prefs.quietHoursStart),
              let qEnd   = parseHHMM(prefs.quietHoursEnd) else { return date }

        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        guard isMinuteInQuietHours(minuteOfDay, start: qStart, end: qEnd) else { return date }

        // Move the notification to quietHoursEnd on the same calendar day.
        var adjustedComps = cal.dateComponents([.year, .month, .day], from: date)
        adjustedComps.hour   = qEnd.0
        adjustedComps.minute = qEnd.1
        adjustedComps.second = 0

        guard var adjusted = cal.date(from: adjustedComps) else { return date }

        // If the end time is earlier in the day than the date (midnight-spanning window),
        // or the result is still in the past, push to the next day.
        if adjusted <= date {
            adjusted = cal.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
        }
        return adjusted
    }

    // MARK: - Private parsing helpers

    /// Parses a "HH:MM" string into `(hour, minute)`. Returns `nil` on bad input.
    func parseHHMM(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), h >= 0, h <= 23,
              let m = Int(parts[1]), m >= 0, m <= 59 else { return nil }
        return (h, m)
    }

    /// Returns `true` when `minuteOfDay` (0–1439) falls within `[start, end)`.
    /// Handles midnight-spanning ranges (e.g. 22:00 → 08:00).
    func isMinuteInQuietHours(
        _ minuteOfDay: Int,
        start: (Int, Int),
        end: (Int, Int)
    ) -> Bool {
        let startMin = start.0 * 60 + start.1
        let endMin   = end.0   * 60 + end.1

        if startMin == endMin { return false }   // zero-width window — nothing is quiet
        if startMin < endMin {
            // Window does not cross midnight, e.g. 09:00–17:00
            return minuteOfDay >= startMin && minuteOfDay < endMin
        } else {
            // Midnight-spanning window, e.g. 22:00–08:00
            return minuteOfDay >= startMin || minuteOfDay < endMin
        }
    }
}
