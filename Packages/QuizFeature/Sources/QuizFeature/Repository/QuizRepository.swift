import Foundation
import Models
import CoreKit

/// A quiz response plus any locally restored answers for the exact same attempt.
public struct LoadedQuiz: Sendable {
    public let response: QuizResponse
    public let selectedAnswers: [String: String]

    public init(response: QuizResponse, selectedAnswers: [String: String] = [:]) {
        self.response = response
        self.selectedAnswers = selectedAnswers
    }
}

/// Result of one explicit submit action. No case represents automatic replay.
public enum QuizSubmissionOutcome: Sendable {
    case graded(QuizAttemptResult, draftCleared: Bool)
    case draftSavedRequiresConnection
    case refreshedAfterStale(LoadedQuiz)
}

public enum QuizDraftError: Error, LocalizedError, Sendable, Equatable {
    case storageUnavailable
    case missingAttemptNumber
    case invalidResponses

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "We couldn't save this quiz draft. Please keep this screen open and try again."
        case .missingAttemptNumber:
            "Refresh this quiz before submitting."
        case .invalidResponses:
            "Answer every question before submitting."
        }
    }
}

/// Data contract for the Quiz feature.
///
/// All grading is server-authoritative: `submit` sends the user's choices and
/// returns the scored ``QuizAttemptResult``. **Never evaluate correctness
/// client-side; never ship answer keys in the bundle.**
public protocol QuizRepository: Sendable {
    /// Fetches a fresh quiz client session for the given chapter.
    func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse

    /// Loads the quiz and restores answers only for the same attempt/question assignment.
    func loadQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> LoadedQuiz

    /// Persists a partial or complete account-scoped draft without submitting it.
    func saveDraft(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        selectedAnswers: [String: String]
    ) async throws

    /// Performs at most one canonical online POST for an explicit user action.
    func submitAttempt(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        responses: [QuizAnswerSubmission]
    ) async throws -> QuizSubmissionOutcome

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

public extension QuizRepository {
    func loadQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> LoadedQuiz {
        LoadedQuiz(response: try await getQuiz(bookId: bookId, n: n, tone: tone))
    }
}
