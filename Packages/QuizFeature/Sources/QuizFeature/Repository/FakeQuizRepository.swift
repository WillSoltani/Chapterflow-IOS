import Models
import CoreKit

/// In-memory ``QuizRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with stubs, then inspect ``recordedResponses`` and ``savedDraft``.
/// An optional `forcedError` makes every call throw.
public actor FakeQuizRepository: QuizRepository {

    public var quizStub: QuizResponse?
    public var submitStub: QuizAttemptResult?
    public var checkStub: QuizCheckResult?
    public var forcedError: AppError?
    public var submitError: AppError?
    public var draftError: QuizDraftError?
    public var restoredAnswers: [String: String] = [:]
    public var submissionOutcome: QuizSubmissionOutcome?

    public private(set) var recordedResponses: [QuizAnswerSubmission] = []
    public private(set) var recordedAttemptNumber: Int?
    public private(set) var savedDraft: [String: String] = [:]
    public private(set) var draftSaveCount: Int = 0
    public private(set) var networkSubmitCount: Int = 0
    public private(set) var eventCount: Int = 0

    /// When `true`, submit confirms the local draft and performs no transport.
    public var simulateOfflineSubmit: Bool = false

    public init(
        quiz: QuizResponse? = nil,
        submitResult: QuizAttemptResult? = nil,
        checkResult: QuizCheckResult? = nil,
        error: AppError? = nil,
        offlineSubmit: Bool = false,
        restoredAnswers: [String: String] = [:],
        submissionOutcome: QuizSubmissionOutcome? = nil
    ) {
        self.quizStub = quiz
        self.submitStub = submitResult
        self.checkStub = checkResult
        self.forcedError = error
        self.simulateOfflineSubmit = offlineSubmit
        self.restoredAnswers = restoredAnswers
        self.submissionOutcome = submissionOutcome
    }

    public func setDraftError(_ error: QuizDraftError?) {
        draftError = error
    }

    public func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        if let e = forcedError { throw e }
        guard let stub = quizStub else { throw AppError.notFound }
        return stub
    }

    public func loadQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> LoadedQuiz {
        LoadedQuiz(
            response: try await getQuiz(bookId: bookId, n: n, tone: tone),
            selectedAnswers: restoredAnswers
        )
    }

    public func saveDraft(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        selectedAnswers: [String: String]
    ) async throws {
        if let draftError { throw draftError }
        if let forcedError { throw forcedError }
        savedDraft = selectedAnswers
        draftSaveCount += 1
    }

    public func submitAttempt(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        responses: [QuizAnswerSubmission]
    ) async throws -> QuizSubmissionOutcome {
        let draft = Dictionary(
            uniqueKeysWithValues: responses.map {
                ($0.questionId, $0.selectedChoiceId)
            }
        )
        try await saveDraft(
            bookId: bookId,
            n: n,
            session: session,
            selectedAnswers: draft
        )
        recordedResponses = responses
        recordedAttemptNumber = session.attemptNumber
        if simulateOfflineSubmit {
            return .draftSavedRequiresConnection
        }
        networkSubmitCount += 1
        if let submitError { throw submitError }
        if let e = forcedError { throw e }
        if let submissionOutcome { return submissionOutcome }
        guard let stub = submitStub else { throw AppError.notFound }
        return .graded(stub, draftCleared: true)
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
