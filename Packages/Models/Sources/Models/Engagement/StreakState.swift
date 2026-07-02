/// The user's reading streak data.
///
/// Returned by `GET /book/me/streak`.
public struct StreakState: Codable, Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let streakShieldsHeld: Int
    public let lastActivityDate: String?
    public let streakHistory: [StreakDay]?

    public init(
        currentStreak: Int,
        longestStreak: Int,
        streakShieldsHeld: Int,
        lastActivityDate: String?,
        streakHistory: [StreakDay]?
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.streakShieldsHeld = streakShieldsHeld
        self.lastActivityDate = lastActivityDate
        self.streakHistory = streakHistory
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

public struct StreakResponse: Codable, Sendable {
    public let streak: StreakState

    public init(streak: StreakState) {
        self.streak = streak
    }
}
