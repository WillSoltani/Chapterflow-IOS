import Foundation

/// A genuine, user-positive moment at which the app *may* ask for an App Store review.
///
/// Only moments that represent a real accomplishment are modelled here — there is
/// deliberately no "failure" or "error" case, so a review can never be requested off
/// the back of a negative outcome. The actual gating (streak thresholds, once-per-version
/// rate limiting) lives in ``ReviewPromptPolicy``.
public enum ReviewPromptMoment: Sendable, Equatable {
    /// The user completed a chapter quiz.
    ///
    /// - Parameters:
    ///   - passed: The server-authoritative grade. The policy only prompts when this is
    ///     `true`; we never grade quizzes client-side, so this value comes straight from
    ///     the server's quiz-submission response.
    ///   - currentStreakDays: The user's active reading streak in days, used to require
    ///     genuine momentum before prompting (see ``ReviewPromptPolicy/minimumStreakForQuizPrompt``).
    case quizCompleted(passed: Bool, currentStreakDays: Int)

    /// The user finished an entire book.
    case bookFinished
}
