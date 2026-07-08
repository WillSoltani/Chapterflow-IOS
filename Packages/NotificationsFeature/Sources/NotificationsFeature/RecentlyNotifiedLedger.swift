import Foundation

// MARK: - RecentlyNotifiedLedger

/// Actor-backed deduplication ledger.
///
/// Tracks which (type, targetId) pairs have been notified today so that
/// `NotificationCoordinator` can suppress local duplicates when a server push
/// has already covered the same topic on the same calendar day.
///
/// Keys are of the form `"<type.rawValue>|<targetId>|<yyyy-MM-dd>"`.
/// Only today's entries are retained; yesterday's keys are silently ignored.
///
/// **In-memory by default.** Pass a `UserDefaults` store to persist entries
/// across app launches (useful when a Notification Service Extension updates
/// the ledger while the app is not running).
public actor RecentlyNotifiedLedger {

    // MARK: - State

    private var entries: Set<String> = []
    private let clock: any NotificationClock

    // MARK: - Init

    public init(clock: any NotificationClock = SystemNotificationClock()) {
        self.clock = clock
    }

    // MARK: - API

    /// `true` when the (type, targetId) pair has already been marked for today.
    public func isRecentlyNotified(type: PushNotificationType, targetId: String?) -> Bool {
        entries.contains(entryKey(type: type, targetId: targetId))
    }

    /// Marks the (type, targetId) pair as notified for today.
    public func markNotified(type: PushNotificationType, targetId: String?) {
        entries.insert(entryKey(type: type, targetId: targetId))
    }

    /// Clears all entries. Useful between test cases.
    public func reset() {
        entries.removeAll()
    }

    // MARK: - Private

    private func entryKey(type: PushNotificationType, targetId: String?) -> String {
        "\(type.rawValue)|\(targetId ?? "")|\(dayKey())"
    }

    private func dayKey() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: clock.now)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 2000,
            comps.month ?? 1,
            comps.day ?? 1
        )
    }
}
