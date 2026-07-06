import ActivityKit
import Foundation

// MARK: - StreakAtRiskAttributes
//
// Compiled by BOTH the ChapterFlow app target AND the ChapterflowWidgets
// extension target. Shows an evening countdown nudging the user to read before
// their streak resets at midnight.

/// Describes a streak-at-risk countdown notification.
public struct StreakAtRiskAttributes: ActivityAttributes, Sendable {
    public typealias ContentState = StreakAtRiskStatus

    // MARK: - Static

    /// Current streak length shown in the title.
    public let streakDays: Int

    public init(streakDays: Int) {
        self.streakDays = streakDays
    }
}

// MARK: - StreakAtRiskStatus (dynamic)

public struct StreakAtRiskStatus: Codable, Hashable, Sendable {
    /// The local midnight deadline by which the user must read to keep the streak.
    public var midnightDeadline: Date
    /// Whether the user has already read today (activity should end if true).
    public var isStreakSaved: Bool

    public init(midnightDeadline: Date, isStreakSaved: Bool = false) {
        self.midnightDeadline = midnightDeadline
        self.isStreakSaved = isStreakSaved
    }
}
