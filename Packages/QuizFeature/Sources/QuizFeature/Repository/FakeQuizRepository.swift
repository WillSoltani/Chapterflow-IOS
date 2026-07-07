import Models
import CoreKit

/// In-memory ``QuizRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with stubs, then inspect ``recordedAnswers`` to assert on what the model submitted.
/// An optional `forcedError` makes every call throw.
public actor FakeQuizRepository: QuizRepository {

    public var quizStub: QuizResponse?
    public var submitStub: QuizAttemptResult?
    public var checkStub: QuizCheckResult?
    public var forcedError: AppError?

    public private(set) var recordedAnswers: [QuizAnswerSubmission] = []
    public private(set) var eventCount: Int = 0

    /// When `true`, `submit()` throws ``QuizSubmissionError/pendingGrading``
    /// to simulate an offline quiz submission that has been queued in the outbox.
    public var simulateOfflineSubmit: Bool = false

    public init(
        quiz: QuizResponse? = nil,
        submitResult: QuizAttemptResult? = nil,
        checkResult: QuizCheckResult? = nil,
        error: AppError? = nil,
        offlineSubmit: Bool = false
    ) {
        self.quizStub = quiz
        self.submitStub = submitResult
        self.checkStub = checkResult
        self.forcedError = error
        self.simulateOfflineSubmit = offlineSubmit
    }

    public func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        if let e = forcedError { throw e }
        guard let stub = quizStub else { throw AppError.notFound }
        return stub
    }

    public func submit(bookId: String, n: Int, answers: [QuizAnswerSubmission]) async throws -> QuizAttemptResult {
        if simulateOfflineSubmit {
            recordedAnswers = answers
            throw QuizSubmissionError.pendingGrading
        }
        if let e = forcedError { throw e }
        recordedAnswers = answers
        guard let stub = submitStub else { throw AppError.notFound }
        return stub
    }

    public func check(bookId: String, n: Int, questionId: String, choiceId: String) async throws -> QuizCheckResult {
        if let e = forcedError { throw e }
        guard let stub = checkStub else { throw AppError.notFound }
        return stub
    }

    public func postEvent(bookId: String, n: Int, event: QuizEventPayload) async throws {
        if let e = forcedError { throw e }
        eventCount += 1
    }
}
