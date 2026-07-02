import Models
import CoreKit

/// Data contract for the Quiz feature.
///
/// All grading is server-authoritative: `submit` sends the user's choices and
/// returns the scored ``QuizAttemptResult``. **Never evaluate correctness
/// client-side; never ship answer keys in the bundle.**
public protocol QuizRepository: Sendable {
    /// Fetches a fresh quiz client session for the given chapter.
    func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse

    /// Submits all selected answers and returns the server-graded result.
    /// This is the **only** place where correctness is determined.
    func submit(
        bookId: String,
        n: Int,
        answers: [QuizAnswerSubmission]
    ) async throws -> QuizAttemptResult

    /// Checks a single answer in real-time (for step-through quiz modes only).
    func check(
        bookId: String,
        n: Int,
        questionId: String,
        choiceId: String
    ) async throws -> QuizCheckResult

    /// Posts a quiz lifecycle event for analytics (fire-and-forget; allowed to throw).
    func postEvent(bookId: String, n: Int, event: QuizEventPayload) async throws
}
