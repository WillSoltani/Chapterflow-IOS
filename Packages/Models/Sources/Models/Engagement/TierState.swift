/// Detailed tier state returned by `POST /book/me/tier`.
///
/// Every field the server may omit is `Optional` so decoding always succeeds.
public struct TierState: Codable, Sendable {

    /// The user's current tier (tolerant — unknown server tiers decode to `.unknown`).
    public let currentTier: TierKey

    /// The next tier the user is working toward, or `nil` when the user is at the top.
    public let nextTier: TierKey?

    /// Overall 0–1 progress fraction toward the next tier.
    public let overallProgress: Double

    /// Per-metric breakdown of what's needed to advance. Absent when the server
    /// doesn't yet return it or the user is already at the top tier.
    public let metrics: TierProgressDetail?

    /// `true` when the server just promoted the user in this response.
    public let recentlyPromoted: Bool?

    /// The tier the user was promoted from (present only when `recentlyPromoted == true`).
    public let previousTier: TierKey?

    public init(
        currentTier: TierKey,
        nextTier: TierKey?,
        overallProgress: Double,
        metrics: TierProgressDetail?,
        recentlyPromoted: Bool?,
        previousTier: TierKey?
    ) {
        self.currentTier = currentTier
        self.nextTier = nextTier
        self.overallProgress = overallProgress
        self.metrics = metrics
        self.recentlyPromoted = recentlyPromoted
        self.previousTier = previousTier
    }
}

// MARK: - TierProgressDetail

/// Granular per-metric breakdown of progress toward the next tier requirement.
public struct TierProgressDetail: Codable, Sendable {

    /// Chapter quiz-pass loops completed toward the next tier threshold.
    public let loopsCompleted: Int

    /// Loops required to advance (nil if the server hasn't provided a target yet).
    public let loopsTarget: Int?

    /// Average quiz score 0–100 over the current tier period.
    public let averageQuizScore: Double

    /// Quiz score threshold required for the next tier.
    public let quizScoreTarget: Double?

    /// Unique book categories the user has explored this tier period.
    public let categoriesExplored: Int

    /// Unique categories required to advance.
    public let categoriesTarget: Int?

    public init(
        loopsCompleted: Int,
        loopsTarget: Int?,
        averageQuizScore: Double,
        quizScoreTarget: Double?,
        categoriesExplored: Int,
        categoriesTarget: Int?
    ) {
        self.loopsCompleted = loopsCompleted
        self.loopsTarget = loopsTarget
        self.averageQuizScore = averageQuizScore
        self.quizScoreTarget = quizScoreTarget
        self.categoriesExplored = categoriesExplored
        self.categoriesTarget = categoriesTarget
    }
}

// MARK: - TierResponse

/// Response wrapper for `POST /book/me/tier`.
public struct TierResponse: Codable, Sendable {
    public let tier: TierState

    public init(tier: TierState) {
        self.tier = tier
    }
}
