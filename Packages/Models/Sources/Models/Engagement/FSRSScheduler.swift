import Foundation

// MARK: - FSRSGrade

/// The four review grades a user can assign to a card.
///
/// Maps 1:1 to the server's `FSRSRating` (1=Again, 2=Hard, 3=Good, 4=Easy).
public enum FSRSGrade: Int, Sendable, CaseIterable, Identifiable {
    case again = 1
    case hard  = 2
    case good  = 3
    case easy  = 4

    public var id: Int { rawValue }

    public var localizedTitle: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    /// A short description shown below each grade button.
    public var intervalHint: String {
        switch self {
        case .again: return "< 1 day"
        case .hard:  return "Shorter"
        case .good:  return "Normal"
        case .easy:  return "Longer"
        }
    }
}

// MARK: - FSRSScheduleInput

/// The card properties consumed by ``FSRSScheduler/schedule(input:grade:now:desiredRetention:)``.
public struct FSRSScheduleInput: Sendable {
    public let stability: Double
    public let difficulty: Double
    public let reps: Int
    public let lapses: Int
    public let state: FsrsCardState
    /// When the card was last reviewed. `nil` for cards that have never been reviewed.
    public let lastReviewAt: Date?

    public init(
        stability: Double,
        difficulty: Double,
        reps: Int,
        lapses: Int,
        state: FsrsCardState,
        lastReviewAt: Date?
    ) {
        self.stability = stability
        self.difficulty = difficulty
        self.reps = reps
        self.lapses = lapses
        self.state = state
        self.lastReviewAt = lastReviewAt
    }

    /// Convenience init from a server `FsrsCard`.
    public init(card: FsrsCard) {
        self.stability = card.stability ?? 0
        self.difficulty = card.difficulty ?? 0
        self.reps = card.reps ?? 0
        self.lapses = card.lapses ?? 0
        self.state = card.state ?? .new
        if let str = card.lastReviewAt {
            self.lastReviewAt = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(str))
                             ?? (try? Date.ISO8601FormatStyle().parse(str))
        } else {
            self.lastReviewAt = nil
        }
    }
}

// MARK: - FSRSScheduleResult

/// The output of a single FSRS scheduling step.
public struct FSRSScheduleResult: Sendable {
    /// New stability (rounded to 2 dp to match the server output).
    public let stability: Double
    /// New difficulty (rounded to 2 dp to match the server output).
    public let difficulty: Double
    /// Elapsed days since the last review (rounded to 2 dp to match the server).
    public let elapsedDays: Double
    /// Number of calendar days until the card is next due.
    public let scheduledDays: Int
    /// Absolute due timestamp computed from `now + scheduledDays * 86400s`.
    public let nextDueDate: Date
    /// New card state after this review.
    public let newState: FsrsCardState
    /// Updated lapse count.
    public let lapses: Int
}

// MARK: - FSRSScheduler

/// Pure, deterministic port of the ChapterFlow server's FSRS-5 scheduler.
///
/// All weights, formulas, and rounding exactly match
/// `app/app/api/book/_lib/fsrs.ts`. Golden-vector unit tests in
/// `FSRSSchedulerTests` verify this port against server-exported vectors so
/// client and server schedules cannot drift.
///
/// ## Usage
/// ```swift
/// let input  = FSRSScheduleInput(card: card)
/// let result = FSRSScheduler.schedule(input: input, grade: .good)
/// // result.scheduledDays, result.nextDueDate, …
/// ```
public enum FSRSScheduler {

    // MARK: - FSRS-5 Default Weights

    /// 19-element weight vector matching `DEFAULT_W` in the server's `fsrs.ts`.
    public static let defaultWeights: [Double] = [
        0.4072, 1.1829, 3.1262, 15.4722, // w[0-3]: init stability per grade
        7.2102, // w[4]: init difficulty base
        0.5316, // w[5]: init difficulty rating-decay coefficient
        1.0651, // w[6]: difficulty delta per grade deviation
        0.0589, // w[7]: mean-reversion weight
        1.5330, // w[8]: recall-stability growth exponent
        0.1670, // w[9]: prior-stability decay exponent
        1.0019, // w[10]: retrievability sensitivity
        1.9395, // w[11]: forget-stability base
        0.1100, // w[12]: difficulty weight in forget-stability
        0.2939, // w[13]: stability weight in forget-stability
        2.2697, // w[14]: retrievability weight in forget-stability
        0.2315, // w[15]: hard-penalty multiplier
        2.9898, // w[16]: easy-bonus multiplier
        0.5163, // w[17]: (not used in review path)
        0.6571, // w[18]: (not used in review path)
    ]

    /// Default desired retention fraction (0.9 = 90%).
    public static let defaultDesiredRetention: Double = 0.9

    // MARK: - Forgetting-curve constants

    /// `DECAY` from the server: `-0.5`.
    static let decay: Double = -0.5

    /// `FACTOR = 0.9^(1/DECAY) - 1 = 0.9^(-2) - 1 = 19/81`.
    /// Pre-computed for reproducibility; matches the JS runtime exactly.
    static let factor: Double = pow(0.9, 1.0 / decay) - 1   // ≈ 0.23456790…

    // MARK: - Public entry point

    /// Computes the next FSRS-5 schedule for a card.
    ///
    /// - Parameters:
    ///   - input: Card scheduling state.
    ///   - grade: The user's rating (Again / Hard / Good / Easy).
    ///   - now: Moment of review. Defaults to `Date()`.
    ///   - desiredRetention: Target retention fraction (default 0.9 = server default).
    /// - Returns: Updated schedule with new stability, difficulty, interval, and due date.
    public static func schedule(
        input: FSRSScheduleInput,
        grade: FSRSGrade,
        now: Date = Date(),
        desiredRetention: Double = defaultDesiredRetention
    ) -> FSRSScheduleResult {
        let isNew = (input.state == .new)

        let elapsedDays: Double
        if isNew || input.lastReviewAt == nil {
            elapsedDays = 0
        } else {
            elapsedDays = max(0, now.timeIntervalSince(input.lastReviewAt!) / 86400)
        }

        let newStability: Double
        let newDifficulty: Double
        let newState: FsrsCardState
        var newLapses = input.lapses

        if isNew {
            newDifficulty = initDifficulty(grade)
            newStability  = initStability(grade)
            newState = (grade == .again) ? .learning : .due
            if grade == .again { newLapses += 1 }
        } else {
            newDifficulty = nextDifficulty(input.difficulty, grade: grade)
            let r = retrievability(elapsedDays: elapsedDays, stability: input.stability)

            if grade == .again {
                // FSRS-5 invariant: a lapse must NEVER increase stability.
                // The raw forget formula can exceed the prior stability for
                // low-difficulty / stale cards — clamp to prior (min) and floor 0.1.
                let rawForget = nextForgetStability(d: input.difficulty, s: input.stability, r: r)
                newStability = max(0.1, min(rawForget, input.stability))
                newState = .relearning
                newLapses += 1
            } else {
                newStability = nextRecallStability(
                    d: input.difficulty, s: input.stability, r: r, grade: grade
                )
                newState = .due
            }
        }

        // Interval is computed from the unrounded stability, matching the server.
        let interval = nextInterval(stability: newStability, desiredRetention: desiredRetention)
        let nextDue  = now.addingTimeInterval(Double(interval) * 86400)

        return FSRSScheduleResult(
            stability:     round2(newStability),
            difficulty:    round2(newDifficulty),
            elapsedDays:   round2(elapsedDays),
            scheduledDays: interval,
            nextDueDate:   nextDue,
            newState:      newState,
            lapses:        newLapses
        )
    }

    // MARK: - Current retrievability

    /// Returns the current retrievability of a card in [0, 1].
    ///
    /// A return of `0` means the card is new or has no positive stability.
    public static func currentRetrievability(input: FSRSScheduleInput, now: Date = Date()) -> Double {
        guard input.state != .new, input.stability > 0, let lastReview = input.lastReviewAt else {
            return 0
        }
        let elapsed = max(0, now.timeIntervalSince(lastReview) / 86400)
        return (retrievability(elapsedDays: elapsed, stability: input.stability) * 1000).rounded() / 1000
    }

    // MARK: - Core formulas (match server 1:1)

    static func initDifficulty(_ grade: FSRSGrade) -> Double {
        let w = defaultWeights
        return clamp(w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1, lo: 1, hi: 10)
    }

    static func initStability(_ grade: FSRSGrade) -> Double {
        let w = defaultWeights
        return max(w[grade.rawValue - 1], 0.1)
    }

    static func nextDifficulty(_ d: Double, grade: FSRSGrade) -> Double {
        let w = defaultWeights
        let newD = d - w[6] * Double(grade.rawValue - 3)
        return clamp(meanRevert(initDifficulty(.easy), current: newD), lo: 1, hi: 10)
    }

    static func meanRevert(_ init_: Double, current: Double) -> Double {
        let w = defaultWeights
        return w[7] * init_ + (1 - w[7]) * current
    }

    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * elapsedDays / stability, decay)
    }

    static func nextRecallStability(d: Double, s: Double, r: Double, grade: FSRSGrade) -> Double {
        let w = defaultWeights
        let hardPenalty = (grade == .hard) ? w[15] : 1.0
        let easyBonus   = (grade == .easy) ? w[16] : 1.0
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    static func nextForgetStability(d: Double, s: Double, r: Double) -> Double {
        let w = defaultWeights
        return w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
    }

    static func nextInterval(stability: Double, desiredRetention: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1.0 / decay) - 1)
        return max(1, Int(raw.rounded()))
    }

    // MARK: - Utility

    static func clamp(_ value: Double, lo: Double, hi: Double) -> Double {
        min(max(value, lo), hi)
    }

    /// Rounds to 2 decimal places, matching `Math.round(x * 100) / 100` in JS.
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
