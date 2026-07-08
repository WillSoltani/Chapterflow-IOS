import Testing
import Foundation
import UserNotifications
import Models
@testable import NotificationsFeature

// MARK: - Test helpers

/// Returns a `Date` for a specific hour/minute using the system calendar (local timezone).
///
/// No timezone override — `Calendar.current` picks the local timezone, so
/// hour/minute comparisons inside the scheduler (which also uses `Calendar.current`)
/// are consistent across all timezones.
private func makeDate(
    year: Int = 2025, month: Int = 6, day: Int = 15,
    hour: Int = 0, minute: Int = 0, second: Int = 0
) -> Date {
    var comps    = DateComponents()
    comps.year   = year
    comps.month  = month
    comps.day    = day
    comps.hour   = hour
    comps.minute = minute
    comps.second = second
    return Calendar.current.date(from: comps) ?? Date.distantPast
}

private func makeCard(
    id: String = "c1",
    dueAt: Date?,
    state: FsrsCardState = .due
) -> FsrsCard {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let dueStr = dueAt.map { iso.string(from: $0) }
    return FsrsCard(
        cardId: id, bookId: "b1", chapterId: "ch1",
        front: "Q", back: "A",
        dueAt: dueStr,
        stability: 1.0, difficulty: 5.0, state: state,
        lastReviewAt: nil, reps: 1, lapses: 0,
        elapsedDays: 1, scheduledDays: 1, retrievability: 0.9
    )
}

private func makeCommitment(
    id: String = "com-1",
    followUpDate: Date,
    status: CommitmentStatus = .active
) -> Commitment {
    Commitment(
        id: id,
        bookId: "b1",
        chapterId: "ch1",
        ifStatement: "I feel stressed",
        thenStatement: "I will read for 10 minutes",
        followUpDate: followUpDate,
        status: status,
        outcome: nil,
        reflection: nil,
        createdAt: makeDate()
    )
}

// MARK: - LocalNotificationScheduler unit tests

@Suite("LocalNotificationScheduler")
@MainActor
struct LocalNotificationSchedulerTests {

    // MARK: - Factory

    func makeScheduler(
        authorized: Bool = true,
        now: Date = makeDate(hour: 10)   // 10:00 by default — well outside quiet hours
    ) -> (LocalNotificationScheduler, SpyNotificationCenter) {
        let spy   = SpyNotificationCenter(authorized: authorized)
        let clock = FixedNotificationClock(now: now)
        let sched = LocalNotificationScheduler(center: spy, clock: clock)
        return (sched, spy)
    }

    // MARK: - Authorization guard

    @Test("skips all scheduling when not authorized")
    func skipsWhenUnauthorized() async {
        let (sched, spy) = makeScheduler(authorized: false)
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [], readToday: false)
        await sched.reschedule(input: input)
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Daily reading reminder

    @Test("schedules repeating daily reading reminder when enabled")
    func schedulesReadingReminder() async {
        let (sched, spy) = makeScheduler()
        let prefs = NotificationPreferences(readingReminderEnabled: true, readingReminderTime: "20:00")
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(spy.hasPending(id: LocalNotificationID.dailyReading))
        let req = spy.addedRequests.first { $0.identifier == LocalNotificationID.dailyReading }
        let trigger = req?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 20)
        #expect(trigger?.dateComponents.minute == 0)
    }

    @Test("cancels reading reminder when disabled in prefs")
    func cancelsReadingReminderWhenDisabled() async {
        let (sched, spy) = makeScheduler()
        var prefs = NotificationPreferences.default
        prefs.readingReminderEnabled = false
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.dailyReading))
        #expect(spy.removedIdentifierBatches.flatMap { $0 }.contains(LocalNotificationID.dailyReading))
    }

    @Test("reschedule replaces previous reading reminder via stable identifier")
    func readingReminderIsIdempotent() async {
        let (sched, spy) = makeScheduler()
        let prefs = NotificationPreferences(readingReminderTime: "20:00")
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)
        await sched.reschedule(input: input)

        // Stable id means only one pending request at a time
        #expect(spy.pendingIdentifiers.filter { $0 == LocalNotificationID.dailyReading }.count == 1)
    }

    @Test("adjusts reading reminder time out of quiet hours")
    func adjustsReadingReminderForQuietHours() async {
        let (sched, spy) = makeScheduler()
        let prefs = NotificationPreferences(
            readingReminderEnabled: true,
            readingReminderTime: "23:00",  // falls inside quiet window
            quietHoursEnabled: true,
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00"
        )
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        let trigger = spy.addedRequests
            .first { $0.identifier == LocalNotificationID.dailyReading }?
            .trigger as? UNCalendarNotificationTrigger
        // Should be pushed to 08:00 (quiet hours end)
        #expect(trigger?.dateComponents.hour == 8)
        #expect(trigger?.dateComponents.minute == 0)
    }

    // MARK: - Streak-at-risk reminder

    @Test("schedules streak-at-risk reminder when not read today and future fire time")
    func schedulesStreakAtRisk() async {
        // 10:00 — 20:00 target is still in the future
        let (sched, spy) = makeScheduler(now: makeDate(hour: 10))
        let prefs = NotificationPreferences(streakReminderEnabled: true)
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(spy.hasPending(id: LocalNotificationID.streakAtRisk))
        let trigger = spy.addedRequests
            .first { $0.identifier == LocalNotificationID.streakAtRisk }?
            .trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == false)
        #expect(trigger?.dateComponents.hour == 20)
    }

    @Test("cancels streak-at-risk reminder when readToday is true")
    func cancelsStreakAtRiskWhenRead() async {
        let (sched, spy) = makeScheduler(now: makeDate(hour: 10))
        let prefs = NotificationPreferences(streakReminderEnabled: true)
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: true)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.streakAtRisk))
        #expect(spy.removedIdentifierBatches.flatMap { $0 }.contains(LocalNotificationID.streakAtRisk))
    }

    @Test("does not schedule streak-at-risk when fire time already passed today")
    func skipsStreakAtRiskWhenPast() async {
        // 21:00 — the 20:00 fire time is already in the past
        let (sched, spy) = makeScheduler(now: makeDate(hour: 21))
        let prefs = NotificationPreferences(streakReminderEnabled: true)
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.streakAtRisk))
    }

    @Test("cancelAtRiskReminder removes the streak-at-risk request")
    func cancelAtRiskAPI() async {
        let (sched, spy) = makeScheduler(now: makeDate(hour: 10))
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [], readToday: false)
        await sched.reschedule(input: input)

        await sched.cancelAtRiskReminder()

        #expect(!spy.hasPending(id: LocalNotificationID.streakAtRisk))
    }

    @Test("cancels streak-at-risk when pref disabled")
    func streakAtRiskDisabledByPref() async {
        let (sched, spy) = makeScheduler(now: makeDate(hour: 10))
        var prefs = NotificationPreferences.default
        prefs.streakReminderEnabled = false
        let input = LocalSchedulerInput(prefs: prefs, cards: [], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.streakAtRisk))
    }

    // MARK: - Review-due reminder

    @Test("schedules review-due reminder for next future due card")
    func schedulesReviewDue() async {
        let now      = makeDate(hour: 10)
        let tomorrow = makeDate(day: 16, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let cards = [makeCard(id: "c1", dueAt: tomorrow)]
        let prefs = NotificationPreferences(reviewReminderEnabled: true)
        let input = LocalSchedulerInput(prefs: prefs, cards: cards, commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(spy.hasPending(id: LocalNotificationID.reviewDue))
        let trigger = spy.addedRequests
            .first { $0.identifier == LocalNotificationID.reviewDue }?
            .trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == false)
        // Trigger should target tomorrow's date
        let cal = Calendar.current
        let triggerDate = trigger.flatMap { cal.date(from: $0.dateComponents) }
        #expect(triggerDate.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
    }

    @Test("cancels review-due reminder when no future cards")
    func cancelsReviewDueWhenNoCards() async {
        let now  = makeDate(hour: 10)
        let past = makeDate(day: 14, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        // Only a past-due card (already overdue — should still have been picked up by the user)
        let cards = [makeCard(id: "c1", dueAt: past)]
        let input = LocalSchedulerInput(prefs: .default, cards: cards, commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.reviewDue))
    }

    @Test("cancelReviewReminder removes the review-due request")
    func cancelReviewAPI() async {
        let now      = makeDate(hour: 10)
        let tomorrow = makeDate(day: 16, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let cards = [makeCard(id: "c1", dueAt: tomorrow)]
        let input = LocalSchedulerInput(prefs: .default, cards: cards, commitments: [], readToday: false)
        await sched.reschedule(input: input)

        await sched.cancelReviewReminder()

        #expect(!spy.hasPending(id: LocalNotificationID.reviewDue))
    }

    @Test("cancels review-due when pref disabled")
    func reviewDueDisabledByPref() async {
        let tomorrow = makeDate(day: 16, hour: 9)
        let (sched, spy) = makeScheduler(now: makeDate(hour: 10))
        var prefs = NotificationPreferences.default
        prefs.reviewReminderEnabled = false
        let input = LocalSchedulerInput(prefs: prefs, cards: [makeCard(dueAt: tomorrow)], commitments: [], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: LocalNotificationID.reviewDue))
    }

    @Test("selects the earliest future due date across multiple cards")
    func picksEarliestDueCard() async {
        let now       = makeDate(hour: 10)
        let tomorrow  = makeDate(day: 16, hour: 9)
        let nextWeek  = makeDate(day: 22, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let cards = [makeCard(id: "c2", dueAt: nextWeek), makeCard(id: "c1", dueAt: tomorrow)]
        let input = LocalSchedulerInput(prefs: .default, cards: cards, commitments: [], readToday: false)

        await sched.reschedule(input: input)

        let trigger = spy.addedRequests
            .first { $0.identifier == LocalNotificationID.reviewDue }?
            .trigger as? UNCalendarNotificationTrigger
        let cal = Calendar.current
        let triggerDate = trigger.flatMap { cal.date(from: $0.dateComponents) }
        #expect(triggerDate.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
    }

    // MARK: - Commitment reminders

    @Test("schedules commitment follow-up for each active future commitment")
    func schedulesCommitmentFollowup() async {
        let now      = makeDate(hour: 10)
        let followUp = makeDate(day: 18, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let commitment = makeCommitment(id: "com-1", followUpDate: followUp)
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [commitment], readToday: false)

        await sched.reschedule(input: input)

        #expect(spy.hasPending(id: "cf.local.commitment.com-1"))
    }

    @Test("does not schedule commitment follow-up for past dates")
    func skipsExpiredCommitment() async {
        let now      = makeDate(hour: 10)
        let past     = makeDate(day: 14, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let commitment = makeCommitment(id: "com-past", followUpDate: past)
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [commitment], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: "cf.local.commitment.com-past"))
    }

    @Test("does not schedule commitment follow-up for done commitments")
    func skipsDoneCommitment() async {
        let now      = makeDate(hour: 10)
        let followUp = makeDate(day: 18, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let commitment = makeCommitment(id: "com-done", followUpDate: followUp, status: .done)
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [commitment], readToday: false)

        await sched.reschedule(input: input)

        #expect(!spy.hasPending(id: "cf.local.commitment.com-done"))
    }

    @Test("cancelCommitmentReminder removes only the target commitment")
    func cancelCommitmentAPI() async {
        let now  = makeDate(hour: 10)
        let f1   = makeDate(day: 17, hour: 9)
        let f2   = makeDate(day: 18, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let c1 = makeCommitment(id: "com-1", followUpDate: f1)
        let c2 = makeCommitment(id: "com-2", followUpDate: f2)
        let input = LocalSchedulerInput(prefs: .default, cards: [], commitments: [c1, c2], readToday: false)
        await sched.reschedule(input: input)

        await sched.cancelCommitmentReminder(id: "com-1")

        #expect(!spy.hasPending(id: "cf.local.commitment.com-1"))
        #expect(spy.hasPending(id: "cf.local.commitment.com-2"))
    }

    // MARK: - Quiet hours helpers (unit-testable pure functions)

    @Test("isMinuteInQuietHours — non-midnight range returns true inside window")
    func quietHoursNonMidnight_Inside() {
        let (sched, _) = makeScheduler()
        // 09:00–17:00, check 12:00 → inside
        #expect(sched.isMinuteInQuietHours(12 * 60, start: (9, 0), end: (17, 0)))
    }

    @Test("isMinuteInQuietHours — non-midnight range returns false outside window")
    func quietHoursNonMidnight_Outside() {
        let (sched, _) = makeScheduler()
        #expect(!sched.isMinuteInQuietHours(18 * 60, start: (9, 0), end: (17, 0)))
    }

    @Test("isMinuteInQuietHours — midnight-spanning range returns true late at night")
    func quietHoursMidnight_LateNight() {
        let (sched, _) = makeScheduler()
        // 22:00–08:00, check 23:00 → inside
        #expect(sched.isMinuteInQuietHours(23 * 60, start: (22, 0), end: (8, 0)))
    }

    @Test("isMinuteInQuietHours — midnight-spanning range returns true early morning")
    func quietHoursMidnight_EarlyMorning() {
        let (sched, _) = makeScheduler()
        // 22:00–08:00, check 07:00 → inside
        #expect(sched.isMinuteInQuietHours(7 * 60, start: (22, 0), end: (8, 0)))
    }

    @Test("isMinuteInQuietHours — midnight-spanning range returns false at midday")
    func quietHoursMidnight_Midday() {
        let (sched, _) = makeScheduler()
        // 22:00–08:00, check 12:00 → outside
        #expect(!sched.isMinuteInQuietHours(12 * 60, start: (22, 0), end: (8, 0)))
    }

    @Test("adjustForQuietHours — does nothing when disabled")
    func adjustDisabled() {
        let (sched, _) = makeScheduler()
        var prefs = NotificationPreferences.default
        prefs.quietHoursEnabled = false
        let date = makeDate(hour: 23)
        #expect(sched.adjustForQuietHours(date, prefs: prefs, cal: .current) == date)
    }

    @Test("adjustForQuietHours — pushes midnight-window time to quietHoursEnd")
    func adjustMidnightWindow() {
        let (sched, _) = makeScheduler()
        let prefs = NotificationPreferences(
            quietHoursEnabled: true,
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00"
        )
        let date = makeDate(hour: 23, minute: 30)  // falls inside 22:00–08:00 window

        let adjusted = sched.adjustForQuietHours(date, prefs: prefs, cal: .current)

        let comps = Calendar.current.dateComponents([.hour, .minute], from: adjusted)
        #expect(comps.hour == 8)
        #expect(comps.minute == 0)
    }

    @Test("adjustForQuietHours — date outside window is unchanged")
    func adjustOutsideWindow() {
        let (sched, _) = makeScheduler()
        let prefs = NotificationPreferences(
            quietHoursEnabled: true,
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00"
        )
        let date = makeDate(hour: 14)   // 14:00 — outside 22:00–08:00
        #expect(sched.adjustForQuietHours(date, prefs: prefs, cal: .current) == date)
    }

    // MARK: - cancelAll

    @Test("cancelAll removes all cf.local.* notifications")
    func cancelAllRemovesOurs() async {
        let now      = makeDate(hour: 10)
        let tomorrow = makeDate(day: 16, hour: 9)
        let followUp = makeDate(day: 17, hour: 9)
        let (sched, spy) = makeScheduler(now: now)
        let commitment = makeCommitment(id: "com-1", followUpDate: followUp)
        let cards = [makeCard(dueAt: tomorrow)]
        let input = LocalSchedulerInput(prefs: .default, cards: cards, commitments: [commitment], readToday: false)
        await sched.reschedule(input: input)

        let beforeCount = spy.pendingIdentifiers.count
        #expect(beforeCount > 0)

        await sched.cancelAll()

        #expect(spy.pendingIdentifiers.isEmpty)
    }

    // MARK: - parseHHMM

    @Test("parseHHMM parses valid time strings")
    func parseHHMM_Valid() {
        let (sched, _) = makeScheduler()
        let result = sched.parseHHMM("20:30")
        #expect(result?.0 == 20)
        #expect(result?.1 == 30)
    }

    @Test("parseHHMM returns nil for bad format")
    func parseHHMM_Invalid() {
        let (sched, _) = makeScheduler()
        #expect(sched.parseHHMM("25:00") == nil)  // hour out of range
        #expect(sched.parseHHMM("not-a-time") == nil)
        #expect(sched.parseHHMM("") == nil)
    }
}
