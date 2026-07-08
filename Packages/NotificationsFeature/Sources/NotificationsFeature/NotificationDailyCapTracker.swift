import Foundation

// MARK: - NotificationDailyCapTracker

/// Actor-backed per-calendar-day notification counter.
///
/// `NotificationCoordinator` consults this before scheduling any `normal` or `low`
/// priority local notification. `.critical` notifications bypass the cap entirely.
///
/// Counts are stored in `UserDefaults` under `"cf.notif.dailyCap.<yyyy-MM-dd>"`.
/// An entry for yesterday or earlier is treated as 0 automatically (the key simply
/// won't be present for today).
public actor NotificationDailyCapTracker {

    /// Default maximum local notifications per calendar day.
    public static let defaultDailyCap = 5

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let clock: any NotificationClock

    // MARK: - Init

    public init(
        defaults: UserDefaults = .standard,
        clock: any NotificationClock = SystemNotificationClock()
    ) {
        self.defaults = defaults
        self.clock = clock
    }

    // MARK: - API

    /// The number of notifications already scheduled today.
    public func scheduledToday() -> Int {
        defaults.integer(forKey: todayKey())
    }

    /// `true` when at least one more notification can be scheduled.
    public func canScheduleAnother(cap: Int = defaultDailyCap) -> Bool {
        scheduledToday() < cap
    }

    /// Increments today's counter by one. Call after every successful add.
    public func recordScheduled() {
        let key = todayKey()
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    /// Resets today's count (for tests).
    public func resetToday() {
        defaults.removeObject(forKey: todayKey())
    }

    // MARK: - Private

    private func todayKey() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: clock.now)
        return "cf.notif.dailyCap.\(comps.year ?? 2000)-\(comps.month ?? 1)-\(comps.day ?? 1)"
    }
}
