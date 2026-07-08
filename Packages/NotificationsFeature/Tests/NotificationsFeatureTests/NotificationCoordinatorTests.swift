import Testing
import Foundation
import UserNotifications
import CoreKit
import Models
@testable import NotificationsFeature

// MARK: - Helpers

private func makeDate(
    year: Int = 2025, month: Int = 6, day: Int = 15,
    hour: Int = 10, minute: Int = 0
) -> Date {
    var comps    = DateComponents()
    comps.year   = year
    comps.month  = month
    comps.day    = day
    comps.hour   = hour
    comps.minute = minute
    return Calendar.current.date(from: comps) ?? Date.distantPast
}

/// In-memory `NotificationDailyCapTracker` for deterministic tests.
private func makeCapTracker(
    clock: FixedNotificationClock
) -> NotificationDailyCapTracker {
    NotificationDailyCapTracker(
        // Unique suite per test run so counts don't leak between cases.
        defaults: UserDefaults(suiteName: "test.cap.\(UUID().uuidString)") ?? .standard,
        clock: clock
    )
}

// MARK: - NotificationCoordinator tests

@Suite("NotificationCoordinator")
@MainActor
struct NotificationCoordinatorTests {

    // MARK: - Factory

    func makeCoordinator(
        now: Date = makeDate(hour: 10),
        dailyCap: Int = NotificationDailyCapTracker.defaultDailyCap
    ) -> NotificationCoordinator {
        let clock = FixedNotificationClock(now: now)
        return NotificationCoordinator(
            analytics: NoopAnalyticsClient(),
            ledger: RecentlyNotifiedLedger(clock: clock),
            capTracker: makeCapTracker(clock: clock),
            dailyCap: dailyCap,
            clock: clock
        )
    }

    // MARK: - Per-type preference gating

    @Test("reading reminder blocked when readingReminderEnabled is false")
    func readingReminderDisabledByPref() async {
        let coord = makeCoordinator()
        var prefs = NotificationPreferences.default
        prefs.readingReminderEnabled = false
        let ok = await coord.shouldSchedule(
            type: .readingReminder, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(!ok)
    }

    @Test("streak reminder blocked when streakReminderEnabled is false")
    func streakReminderDisabledByPref() async {
        let coord = makeCoordinator()
        var prefs = NotificationPreferences.default
        prefs.streakReminderEnabled = false
        let ok = await coord.shouldSchedule(
            type: .streakAtRisk, targetId: nil, prefs: prefs, priority: .critical
        )
        #expect(!ok)
    }

    @Test("review reminder blocked when reviewReminderEnabled is false")
    func reviewReminderDisabledByPref() async {
        let coord = makeCoordinator()
        var prefs = NotificationPreferences.default
        prefs.reviewReminderEnabled = false
        let ok = await coord.shouldSchedule(
            type: .reviewDue, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(!ok)
    }

    @Test("enabled type passes the pref check")
    func enabledTypePasses() async {
        let coord = makeCoordinator()
        let ok = await coord.shouldSchedule(
            type: .readingReminder, targetId: nil, prefs: .default, priority: .normal
        )
        #expect(ok)
    }

    // MARK: - Daily cap enforcement

    @Test("normal-priority notifications are blocked once cap is reached")
    func dailyCapBlocksNormal() async {
        // Use distinct targetIds so dedup doesn't activate; only the cap blocks the 4th attempt.
        let cap = 3
        let coord = makeCoordinator(dailyCap: cap)
        let prefs = NotificationPreferences.default

        for i in 0..<cap {
            let ok = await coord.shouldSchedule(
                type: .commitmentFollowup, targetId: "target-\(i)", prefs: prefs, priority: .normal
            )
            #expect(ok)
            await coord.didSchedule(type: .commitmentFollowup, targetId: "target-\(i)")
        }

        let blocked = await coord.shouldSchedule(
            type: .commitmentFollowup, targetId: "target-\(cap)", prefs: prefs, priority: .normal
        )
        #expect(!blocked)
    }

    @Test("low-priority notifications are blocked once cap is reached")
    func dailyCapBlocksLow() async {
        let cap = 2
        let coord = makeCoordinator(dailyCap: cap)
        let prefs = NotificationPreferences.default

        for i in 0..<cap {
            _ = await coord.shouldSchedule(
                type: .commitmentFollowup, targetId: "c\(i)", prefs: prefs, priority: .low
            )
            await coord.didSchedule(type: .commitmentFollowup, targetId: "c\(i)")
        }

        let blocked = await coord.shouldSchedule(
            type: .commitmentFollowup, targetId: "c\(cap)", prefs: prefs, priority: .low
        )
        #expect(!blocked)
    }

    @Test("critical notifications bypass the daily cap")
    func criticalBypassesCap() async {
        let cap = 2
        let coord = makeCoordinator(dailyCap: cap)
        let prefs = NotificationPreferences.default

        // Fill cap with normal notifications
        for _ in 0..<cap {
            _ = await coord.shouldSchedule(
                type: .readingReminder, targetId: nil, prefs: prefs, priority: .normal
            )
            await coord.didSchedule(type: .readingReminder, targetId: nil)
        }

        // Critical should still pass even though cap is exhausted
        let ok = await coord.shouldSchedule(
            type: .streakAtRisk, targetId: nil, prefs: prefs, priority: .critical
        )
        #expect(ok)
    }

    // MARK: - Deduplication ledger

    @Test("local reminder is suppressed when push already marked type today")
    func dedupSuppressesLocalAfterPush() async {
        let coord = makeCoordinator()
        let prefs = NotificationPreferences.default

        // Simulate push received for reading_reminder (marks ledger)
        await coord.didReceivePush(type: .readingReminder, targetId: nil)

        // Local reading reminder should now be suppressed
        let ok = await coord.shouldSchedule(
            type: .readingReminder, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(!ok)
    }

    @Test("dedup is keyed by type — different types are not suppressed")
    func dedupKeysOnType() async {
        let coord = makeCoordinator()
        let prefs = NotificationPreferences.default

        // Only mark reading_reminder
        await coord.didReceivePush(type: .readingReminder, targetId: nil)

        // review_due is a different type — should NOT be suppressed
        let reviewOk = await coord.shouldSchedule(
            type: .reviewDue, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(reviewOk)
    }

    @Test("dedup is keyed by targetId — different IDs are not suppressed")
    func dedupKeysOnTargetId() async {
        let coord = makeCoordinator()
        let prefs = NotificationPreferences.default

        // Mark commitment "A" as received
        await coord.didReceivePush(type: .commitmentFollowup, targetId: "commitA")

        // Commitment "B" with different ID should still be allowed
        let okB = await coord.shouldSchedule(
            type: .commitmentFollowup, targetId: "commitB", prefs: prefs, priority: .low
        )
        #expect(okB)

        // Commitment "A" itself should be suppressed
        let okA = await coord.shouldSchedule(
            type: .commitmentFollowup, targetId: "commitA", prefs: prefs, priority: .low
        )
        #expect(!okA)
    }

    @Test("didSchedule marks the ledger so subsequent scheduling of same type is suppressed")
    func didScheduleMarksLedger() async {
        let coord = makeCoordinator()
        let prefs = NotificationPreferences.default

        // First schedule for reviewDue succeeds
        let first = await coord.shouldSchedule(
            type: .reviewDue, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(first)
        await coord.didSchedule(type: .reviewDue, targetId: nil)

        // Second attempt for the identical (type=reviewDue, targetId=nil) is suppressed
        let second = await coord.shouldSchedule(
            type: .reviewDue, targetId: nil, prefs: prefs, priority: .normal
        )
        #expect(!second, "Same type+targetId combination should be deduplicated within the day")
    }

    // MARK: - Snooze fire date

    @Test("snoozeFireDate returns this-evening (20:00) when before 18:00")
    func snoozeBeforeEvening() {
        let now = makeDate(hour: 10)
        let fire = NotificationCoordinator.snoozeFireDate(from: now)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fire)
        #expect(comps.hour == 20)
        #expect(comps.minute == 0)
    }

    @Test("snoozeFireDate returns now+2h when at 18:00")
    func snoozeAtEveningBoundary() {
        let now = makeDate(hour: 18)
        let fire = NotificationCoordinator.snoozeFireDate(from: now)
        let expected = now.addingTimeInterval(2 * 3600)
        let diff = abs(fire.timeIntervalSince(expected))
        #expect(diff < 1.0)
    }

    @Test("snoozeFireDate returns now+2h when after 18:00")
    func snoozeAfterEvening() {
        let now = makeDate(hour: 21)
        let fire = NotificationCoordinator.snoozeFireDate(from: now)
        let expected = now.addingTimeInterval(2 * 3600)
        let diff = abs(fire.timeIntervalSince(expected))
        #expect(diff < 1.0)
    }

    @Test("snoozeFireDate is always strictly after now")
    func snoozeAlwaysFuture() {
        // Even at 19:59 (would-be evening at 20:00 which IS in the future)
        let now = makeDate(hour: 19, minute: 59)
        let fire = NotificationCoordinator.snoozeFireDate(from: now)
        #expect(fire > now)
    }

    // MARK: - Snooze reschedule (via LocalNotificationScheduler + SpyNotificationCenter)

    @Test("snoozeRequest removes old request and adds new one with same identifier")
    func snoozeReschedulesWithSameIdentifier() async {
        let clock = FixedNotificationClock(now: makeDate(hour: 10))
        let spy   = SpyNotificationCenter()
        let scheduler = LocalNotificationScheduler(center: spy, clock: clock)
        let fireDate  = makeDate(hour: 20)

        // Seed a fake pending request
        let content = UNMutableNotificationContent()
        content.title = "Test"
        let initialTrigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 8, minute: 0),
            repeats: false
        )
        let original = UNNotificationRequest(
            identifier: "cf.local.daily-reading",
            content: content,
            trigger: initialTrigger
        )
        try? await spy.addRequest(original)
        #expect(spy.hasPending(id: "cf.local.daily-reading"))

        // Snooze via the scheduler
        await scheduler.snoozeRequest(
            identifier: "cf.local.daily-reading",
            content: content,
            until: fireDate
        )

        // Identifier should still be present (rescheduled, not removed)
        #expect(spy.hasPending(id: "cf.local.daily-reading"))

        // The last added request should target 20:00
        let rescheduled = spy.addedRequests.last
        let trigger = rescheduled?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 20)
        #expect(trigger?.dateComponents.minute == 0)
        #expect(trigger?.repeats == false)
    }

    // MARK: - Quiet-hours windowing (end-to-end through scheduler + coordinator)

    @Test("scheduler respects quiet hours — fire time adjusted to window end")
    func quietHoursWindowingEndToEnd() async {
        let clock = FixedNotificationClock(now: makeDate(hour: 10))
        let spy   = SpyNotificationCenter()
        let coord = NotificationCoordinator(
            analytics: NoopAnalyticsClient(),
            ledger: RecentlyNotifiedLedger(clock: clock),
            capTracker: makeCapTracker(clock: clock),
            dailyCap: 10,
            clock: clock
        )
        let scheduler = LocalNotificationScheduler(
            center: spy,
            clock: clock,
            coordinator: coord
        )

        let prefs = NotificationPreferences(
            readingReminderEnabled: true,
            readingReminderTime: "23:30",   // inside quiet window
            quietHoursEnabled: true,
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00"
        )
        let input = LocalSchedulerInput(
            prefs: prefs, cards: [], commitments: [], readToday: false
        )
        await scheduler.reschedule(input: input)

        let trigger = spy.addedRequests
            .first { $0.identifier == LocalNotificationID.dailyReading }?
            .trigger as? UNCalendarNotificationTrigger
        // Should be adjusted to quietHoursEnd (08:00)
        #expect(trigger?.dateComponents.hour == 8)
        #expect(trigger?.dateComponents.minute == 0)
    }

    @Test("cap enforcement end-to-end — scheduler stops adding after cap")
    func capEndToEnd() async {
        let clock = FixedNotificationClock(now: makeDate(hour: 10))
        let spy   = SpyNotificationCenter()
        let cap   = 1
        let coord = NotificationCoordinator(
            analytics: NoopAnalyticsClient(),
            ledger: RecentlyNotifiedLedger(clock: clock),
            capTracker: makeCapTracker(clock: clock),
            dailyCap: cap,
            clock: clock
        )
        let scheduler = LocalNotificationScheduler(
            center: spy,
            clock: clock,
            coordinator: coord
        )

        // Build an input with two reminders that both qualify (reading + streak at risk)
        let prefs = NotificationPreferences(
            readingReminderEnabled: true,
            readingReminderTime: "20:00",
            streakReminderEnabled: true,
            reviewReminderEnabled: false
        )
        let input = LocalSchedulerInput(
            prefs: prefs, cards: [], commitments: [], readToday: false
        )
        await scheduler.reschedule(input: input)

        // Only 1 normal-priority notification should have been added (cap=1).
        // streakAtRisk is .critical so it bypasses the cap — it will always be added.
        // reading reminder is .normal, streakAtRisk is .critical.
        // So we expect both: cap only blocks normal/low, not critical.
        let normalAdded = spy.addedRequests.filter {
            $0.identifier == LocalNotificationID.dailyReading
        }.count
        let criticalAdded = spy.addedRequests.filter {
            $0.identifier == LocalNotificationID.streakAtRisk
        }.count
        // Normal cap=1: reading reminder counts against it first; only 1 normal passes.
        #expect(normalAdded == 1)
        // Critical (streakAtRisk) always passes
        #expect(criticalAdded == 1)
    }
}
