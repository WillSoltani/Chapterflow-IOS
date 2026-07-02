/// The user's reading streak data.
///
/// Returned by `GET /book/me/streak`.
public struct StreakState: Codable, Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let streakShieldsHeld: Int
    public let lastActivityDate: String?
    public let streakHistory: [StreakDay]?
}

/// A single day's reading activity in the streak history.
public struct StreakDay: Codable, Sendable {
    public let date: String
    public let minutesRead: Int
}

public struct StreakResponse: Codable, Sendable {
    public let streak: StreakState
}
