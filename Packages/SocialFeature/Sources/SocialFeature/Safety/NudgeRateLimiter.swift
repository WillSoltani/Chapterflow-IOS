import Foundation

/// Enforces a per-partner nudge rate limit on the client side.
///
/// **Window:** 24 hours. **Cap:** `maxNudgesPerWindow` per partner per window.
/// Usage timestamps are persisted in `UserDefaults` so the cap survives
/// app restarts.
///
/// The server is the authoritative gatekeeper (and will return `.rateLimited`
/// if the cap is exceeded server-side). This limiter provides fast, friendly
/// UI feedback before attempting the network round-trip.
public final class NudgeRateLimiter: @unchecked Sendable {

    // MARK: - Shared singleton

    public static let shared = NudgeRateLimiter()

    // MARK: - Configuration

    /// Maximum nudges allowed per partner within one `windowDuration`.
    public let maxNudgesPerWindow: Int

    /// Duration of one rate-limit window (default: 24 hours).
    public let windowDuration: TimeInterval

    private let defaults: UserDefaults
    private let storageKey = "cf.nudgeRateLimit.usage"

    // MARK: - Init

    public init(
        maxNudgesPerWindow: Int = 3,
        windowDuration: TimeInterval = 60 * 60 * 24,
        defaults: UserDefaults = .standard
    ) {
        self.maxNudgesPerWindow = maxNudgesPerWindow
        self.windowDuration = windowDuration
        self.defaults = defaults
    }

    // MARK: - Public API

    /// `true` if the current user may send another nudge to `partnerId` right now.
    public func canSendNudge(to partnerId: String) -> Bool {
        nudgesRemaining(for: partnerId) > 0
    }

    /// Number of nudges still allowed in the current window for `partnerId`.
    public func nudgesRemaining(for partnerId: String) -> Int {
        max(0, maxNudgesPerWindow - activeCount(for: partnerId))
    }

    /// Earliest `Date` at which the next nudge will be permitted for `partnerId`,
    /// or `nil` if a nudge can be sent right now.
    public func nextAvailableDate(for partnerId: String) -> Date? {
        guard !canSendNudge(to: partnerId) else { return nil }
        let cutoff = Date().addingTimeInterval(-windowDuration)
        let sorted = timestamps(for: partnerId).filter { $0 > cutoff }.sorted()
        guard let oldest = sorted.first else { return nil }
        return oldest.addingTimeInterval(windowDuration)
    }

    /// Records a nudge sent to `partnerId`. **Call only after the server request succeeds.**
    public func recordNudge(to partnerId: String) {
        var all = loadAll()
        var ts = all[partnerId] ?? []
        ts.append(Date())
        all[partnerId] = ts
        save(all)
    }

    /// Clears all usage records for `partnerId` (useful after unblocking or in tests).
    public func resetUsage(for partnerId: String) {
        var all = loadAll()
        all.removeValue(forKey: partnerId)
        save(all)
    }

    // MARK: - Private

    private func activeCount(for partnerId: String) -> Int {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        return timestamps(for: partnerId).filter { $0 > cutoff }.count
    }

    private func timestamps(for partnerId: String) -> [Date] {
        loadAll()[partnerId] ?? []
    }

    private func loadAll() -> [String: [Date]] {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: [Date]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ usage: [String: [Date]]) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
