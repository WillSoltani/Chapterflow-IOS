/// The user's reading streak data.
///
/// Returned by `GET /book/me/streak`.
public struct StreakState: Codable, Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let streakShieldsHeld: Int
    public let lastActivityDate: String?
    public let streakHistory: [StreakDay]?
    /// 30-day reading-activity array (one entry per day, ordered oldest-first).
    public let consistencyLast30: [StreakDay]?
    /// Milestone day-counts the user has crossed (e.g. [7, 14, 30]).
    public let milestonesReached: [Int]?

    public init(
        currentStreak: Int,
        longestStreak: Int,
        streakShieldsHeld: Int,
        lastActivityDate: String?,
        streakHistory: [StreakDay]?,
        consistencyLast30: [StreakDay]? = nil,
        milestonesReached: [Int]? = nil
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.streakShieldsHeld = streakShieldsHeld
        self.lastActivityDate = lastActivityDate
        self.streakHistory = streakHistory
        self.consistencyLast30 = consistencyLast30
        self.milestonesReached = milestonesReached
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // The deployed /book/me/streak sends `shieldsHeld` (not `streakShieldsHeld`),
    // `lastActiveDate` (not `lastActivityDate`), and a numeric
    // `consistencyScore` where the canonical shape has a `consistencyLast30`
    // day array (type-mismatched alternates simply stay nil — never throw).

    private enum WireKeys: String, CodingKey {
        case currentStreak, longestStreak
        case streakShieldsHeld, shieldsHeld
        case lastActivityDate, lastActiveDate
        case streakHistory, consistencyLast30, milestonesReached
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        currentStreak = c.decodeFirst(Int.self, keys: [.currentStreak]) ?? 0
        longestStreak = c.decodeFirst(Int.self, keys: [.longestStreak]) ?? 0
        streakShieldsHeld = c.decodeFirst(Int.self, keys: [.streakShieldsHeld, .shieldsHeld]) ?? 0
        lastActivityDate = c.decodeFirst(String.self, keys: [.lastActivityDate, .lastActiveDate])
        streakHistory = try? c.decodeLossy(StreakDay.self, forKey: .streakHistory)
        consistencyLast30 = try? c.decodeLossy(StreakDay.self, forKey: .consistencyLast30)
        milestonesReached = c.decodeFirst([Int].self, keys: [.milestonesReached])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(currentStreak, forKey: .currentStreak)
        try c.encode(longestStreak, forKey: .longestStreak)
        try c.encode(streakShieldsHeld, forKey: .streakShieldsHeld)
        try c.encodeIfPresent(lastActivityDate, forKey: .lastActivityDate)
        try c.encodeIfPresent(streakHistory, forKey: .streakHistory)
        try c.encodeIfPresent(consistencyLast30, forKey: .consistencyLast30)
        try c.encodeIfPresent(milestonesReached, forKey: .milestonesReached)
    }
}

/// A single day's reading activity in the streak history.
public struct StreakDay: Codable, Sendable {
    public let date: String
    public let minutesRead: Int

    public init(date: String, minutesRead: Int) {
        self.date = date
        self.minutesRead = minutesRead
    }
}

/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route returns the streak object FLAT (no `streak` wrapper);
/// caches/fixtures use the canonical `{streak: {…}}`. Both decode.
public struct StreakResponse: Codable, Sendable {
    public let streak: StreakState

    public init(streak: StreakState) {
        self.streak = streak
    }

    private enum CodingKeys: String, CodingKey { case streak }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = container.decodeFirst(StreakState.self, keys: [.streak]) {
            self.streak = wrapped
        } else {
            self.streak = try StreakState(from: decoder)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(streak, forKey: .streak)
    }
}
