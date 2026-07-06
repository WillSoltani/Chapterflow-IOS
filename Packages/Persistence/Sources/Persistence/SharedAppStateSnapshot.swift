import Foundation

/// A compact, Codable snapshot of the user's current reading state.
///
/// Written by the main app (via ``SharedStateWriter``) and read by widget/extension
/// targets via ``SharedStateReader``. All fields decode leniently — missing or
/// unrecognised values fall back to sane defaults, so older-schema snapshots never
/// crash a widget.
public struct SharedAppStateSnapshot: Codable, Sendable, Equatable {
    /// Current reading streak in calendar days.
    public var streakDays: Int
    /// The user's longest streak ever recorded.
    public var longestStreak: Int
    /// Streak shields the user currently holds.
    public var streakShieldsHeld: Int
    /// True when the streak is > 0, no reading has happened today, and it is past 8 pm local time.
    public var streakAtRisk: Bool
    /// The `bookId` of the most-recently-read book, or nil if none.
    public var continueBookId: String?
    /// Human-readable title of the continue-reading book.
    public var continueBookTitle: String?
    /// Emoji glyph of the book cover (rendered client-side, no network needed).
    public var continueBookCoverEmoji: String?
    /// Hex/CSS colour string for the cover gradient background.
    public var continueBookCoverColor: String?
    /// Chapter number the user was last reading.
    public var continueChapterNumber: Int?
    /// Overall book-completion fraction (0–1): completedChapters / totalChapters.
    public var continueProgress: Double?
    /// Number of FSRS review cards currently due.
    public var dueReviewCount: Int
    /// The user's daily reading goal in minutes (one of 10 / 20 / 30).
    public var dailyGoalMinutes: Int
    /// Minutes read today (for computing the goal-ring fraction in widgets).
    public var goalProgressMinutes: Int
    /// Wall-clock timestamp of the last write (used by widgets to detect staleness).
    public var lastUpdated: Date

    public init(
        streakDays: Int = 0,
        longestStreak: Int = 0,
        streakShieldsHeld: Int = 0,
        streakAtRisk: Bool = false,
        continueBookId: String? = nil,
        continueBookTitle: String? = nil,
        continueBookCoverEmoji: String? = nil,
        continueBookCoverColor: String? = nil,
        continueChapterNumber: Int? = nil,
        continueProgress: Double? = nil,
        dueReviewCount: Int = 0,
        dailyGoalMinutes: Int = DailyGoalStore.defaultGoalMinutes,
        goalProgressMinutes: Int = 0,
        lastUpdated: Date = .distantPast
    ) {
        self.streakDays = streakDays
        self.longestStreak = longestStreak
        self.streakShieldsHeld = streakShieldsHeld
        self.streakAtRisk = streakAtRisk
        self.continueBookId = continueBookId
        self.continueBookTitle = continueBookTitle
        self.continueBookCoverEmoji = continueBookCoverEmoji
        self.continueBookCoverColor = continueBookCoverColor
        self.continueChapterNumber = continueChapterNumber
        self.continueProgress = continueProgress
        self.dueReviewCount = dueReviewCount
        self.dailyGoalMinutes = dailyGoalMinutes
        self.goalProgressMinutes = goalProgressMinutes
        self.lastUpdated = lastUpdated
    }

    // MARK: - Codable (tolerant: missing keys use defaults instead of throwing)

    private enum CodingKeys: String, CodingKey {
        case streakDays, longestStreak, streakShieldsHeld, streakAtRisk
        case continueBookId, continueBookTitle
        case continueBookCoverEmoji, continueBookCoverColor
        case continueChapterNumber, continueProgress
        case dueReviewCount, dailyGoalMinutes, goalProgressMinutes, lastUpdated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streakDays          = (try? c.decode(Int.self, forKey: .streakDays))          ?? 0
        longestStreak       = (try? c.decode(Int.self, forKey: .longestStreak))       ?? 0
        streakShieldsHeld   = (try? c.decode(Int.self, forKey: .streakShieldsHeld))   ?? 0
        streakAtRisk        = (try? c.decode(Bool.self, forKey: .streakAtRisk))        ?? false
        continueBookId      = try? c.decode(String.self, forKey: .continueBookId)
        continueBookTitle   = try? c.decode(String.self, forKey: .continueBookTitle)
        continueBookCoverEmoji  = try? c.decode(String.self, forKey: .continueBookCoverEmoji)
        continueBookCoverColor  = try? c.decode(String.self, forKey: .continueBookCoverColor)
        continueChapterNumber   = try? c.decode(Int.self,    forKey: .continueChapterNumber)
        continueProgress        = try? c.decode(Double.self, forKey: .continueProgress)
        dueReviewCount      = (try? c.decode(Int.self, forKey: .dueReviewCount))      ?? 0
        dailyGoalMinutes    = (try? c.decode(Int.self, forKey: .dailyGoalMinutes))    ?? DailyGoalStore.defaultGoalMinutes
        goalProgressMinutes = (try? c.decode(Int.self, forKey: .goalProgressMinutes)) ?? 0
        lastUpdated         = (try? c.decode(Date.self, forKey: .lastUpdated))         ?? .distantPast
    }

    // MARK: - Derived

    /// Fraction of the daily goal met today (0–1, capped at 1).
    public var goalFraction: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(goalProgressMinutes) / Double(dailyGoalMinutes))
    }

    /// True once the user has hit or exceeded their daily goal today.
    public var isDailyGoalMet: Bool { goalFraction >= 1.0 }

    /// Whether this snapshot contains a valid continue-reading entry.
    public var hasContinueReading: Bool { continueBookId != nil }
}
