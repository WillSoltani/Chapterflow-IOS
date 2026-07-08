import Foundation
import CoreKit

// MARK: - NotificationPriority

/// Scheduling priority used by `NotificationCoordinator` to decide which reminders
/// survive the daily cap.
///
/// `.critical` notifications always pass through — they bypass the per-day cap.
/// `.normal` and `.low` are counted against it in first-come, first-served order.
public enum NotificationPriority: Int, Comparable, Sendable {
    case low      = 1
    case normal   = 2
    case critical = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - PushNotificationType priority extension

public extension PushNotificationType {
    /// Default scheduling priority for this notification type.
    var coordinatorPriority: NotificationPriority {
        switch self {
        case .streakAtRisk, .badgeEarned, .tierUp:
            return .critical
        case .readingReminder, .streakMilestone, .reviewDue, .insightSpark:
            return .normal
        case .commitmentFollowup, .partnerNudge, .eventReminder,
             .scenarioApproved, .scenarioRejected, .unknown:
            return .low
        }
    }
}

// MARK: - CoordinatorGate

/// Gate injected into `LocalNotificationScheduler`.
///
/// The scheduler calls `shouldSchedule` before every `UNNotificationRequest` add
/// and `didSchedule` immediately after a successful add.
public protocol CoordinatorGate: Sendable {
    /// Returns `true` when the notification should proceed to scheduling.
    func shouldSchedule(
        type: PushNotificationType,
        targetId: String?,
        prefs: NotificationPreferences,
        priority: NotificationPriority
    ) async -> Bool

    /// Records that a notification was successfully added to the system.
    func didSchedule(type: PushNotificationType, targetId: String?) async
}

// MARK: - NotificationCoordinator

/// The single coordinator that all local-notification scheduling routes through.
///
/// **Responsibilities:**
/// - **Per-type prefs**: a disabled type is never scheduled.
/// - **Daily cap**: `normal`/`low` notifications are counted; once the configured
///   daily maximum is reached, remaining reminders are dropped. `.critical`
///   notifications always pass.
/// - **De-duplication**: if a server push already covered a (type, targetId, day)
///   combination, the local duplicate is suppressed via `RecentlyNotifiedLedger`.
/// - **Analytics**: fires `notificationSent` / `notificationReceived` /
///   `notificationOpened` events through the injected `AnalyticsClient`.
/// - **Snooze helper**: `snoozeFireDate(from:cal:)` computes the correct target
///   fire time ("this evening" or now+2h).
///
/// **Quiet hours** are enforced at the `LocalNotificationScheduler` level
/// (fire-time adjustment); this coordinator respects per-type prefs only and
/// does not duplicate that logic.
///
/// **Wiring (P9.7):**
/// 1. At app startup: `NotificationCoordinator.configure(analytics:)`.
/// 2. Pass `NotificationCoordinator.shared` to `LocalNotificationScheduler.init`.
/// 3. In `AppDelegate.userNotificationCenter(_:willPresent:)`:
///    call `NotificationCoordinator.shared.didReceivePush(type:targetId:)`.
/// 4. In `PushRoutingBridge.didReceiveResponse`: the bridge already calls the
///    coordinator for open attribution (wired via `notificationCoordinator`).
public actor NotificationCoordinator: CoordinatorGate {

    // MARK: - Shared singleton

    public static let shared = NotificationCoordinator()

    /// Replaces the no-op analytics client on the shared coordinator.
    /// Call once at app startup, before any notifications can be scheduled.
    public nonisolated static func configure(analytics: any AnalyticsClient) {
        Task { await shared.setAnalytics(analytics) }
    }

    // MARK: - State

    private var analytics: any AnalyticsClient
    private let ledger: RecentlyNotifiedLedger
    private let capTracker: NotificationDailyCapTracker
    let dailyCap: Int   // internal for tests
    private let clock: any NotificationClock
    private let log = AppLog(category: .notifications)

    // MARK: - Init

    public init(
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        ledger: RecentlyNotifiedLedger = RecentlyNotifiedLedger(),
        capTracker: NotificationDailyCapTracker = NotificationDailyCapTracker(),
        dailyCap: Int = NotificationDailyCapTracker.defaultDailyCap,
        clock: any NotificationClock = SystemNotificationClock()
    ) {
        self.analytics   = analytics
        self.ledger      = ledger
        self.capTracker  = capTracker
        self.dailyCap    = dailyCap
        self.clock       = clock
    }

    // MARK: - CoordinatorGate

    public func shouldSchedule(
        type: PushNotificationType,
        targetId: String?,
        prefs: NotificationPreferences,
        priority: NotificationPriority
    ) async -> Bool {
        // 1. Per-type preference check
        guard isTypeEnabled(type, prefs: prefs) else {
            log.debug("[\(type.rawValue)] blocked — type disabled in prefs")
            return false
        }

        // 2. Daily cap (critical bypasses)
        if priority < .critical {
            guard await capTracker.canScheduleAnother(cap: dailyCap) else {
                log.info("[\(type.rawValue)] blocked — daily cap (\(dailyCap)) reached")
                return false
            }
        }

        // 3. Dedup: suppress if a push already covered this type+target today
        if await ledger.isRecentlyNotified(type: type, targetId: targetId) {
            log.info("[\(type.rawValue)] suppressed — push already covered today")
            return false
        }

        return true
    }

    public func didSchedule(type: PushNotificationType, targetId: String?) async {
        analytics.track(.notificationSent(type: type.rawValue))
        await capTracker.recordScheduled()
        await ledger.markNotified(type: type, targetId: targetId)
        log.debug("Scheduled & tracked: \(type.rawValue)")
    }

    // MARK: - Push received

    /// Call when a server push is received (foreground `willPresent` or silent background).
    public func didReceivePush(type: PushNotificationType, targetId: String?) async {
        analytics.track(.notificationReceived(type: type.rawValue))
        await ledger.markNotified(type: type, targetId: targetId)
        log.info("Push received: \(type.rawValue)")
    }

    // MARK: - Notification opened

    /// Call when the user taps a notification or triggers an inline action.
    /// `action` is the `UNNotificationResponse.actionIdentifier` value.
    public func didOpenNotification(
        type: PushNotificationType,
        action: String,
        url: URL
    ) async {
        analytics.track(.notificationOpened(type: type.rawValue, action: action))
        log.info("Notification opened: \(type.rawValue) action=\(action)")
    }

    // MARK: - Snooze fire date (nonisolated utility)

    /// Computes the target fire time for a snoozed notification.
    ///
    /// - Before 18:00 local time → schedules for the **same evening at 20:00**.
    /// - 18:00 or later → schedules for **`now` + 2 hours**.
    ///
    /// Always returns a date strictly after `now`.
    public static nonisolated func snoozeFireDate(
        from now: Date,
        cal: Calendar = .current
    ) -> Date {
        let hour = cal.component(.hour, from: now)
        if hour < 18 {
            var eveningComps = cal.dateComponents([.year, .month, .day], from: now)
            eveningComps.hour   = 20
            eveningComps.minute = 0
            eveningComps.second = 0
            if let evening = cal.date(from: eveningComps), evening > now {
                return evening
            }
        }
        return now.addingTimeInterval(2 * 3600)
    }

    // MARK: - Private helpers

    private func setAnalytics(_ client: any AnalyticsClient) {
        analytics = client
    }

    /// Returns `true` when `type` is permitted by the user's current preferences.
    private func isTypeEnabled(_ type: PushNotificationType, prefs: NotificationPreferences) -> Bool {
        switch type {
        case .readingReminder:
            return prefs.readingReminderEnabled
        case .streakAtRisk:
            return prefs.streakReminderEnabled
        case .reviewDue:
            return prefs.reviewReminderEnabled
        case .badgeEarned, .tierUp, .streakMilestone:
            return prefs.badgeAlertsEnabled
        case .commitmentFollowup, .partnerNudge, .insightSpark,
             .eventReminder, .scenarioApproved, .scenarioRejected, .unknown:
            return prefs.channels.push
        }
    }
}
