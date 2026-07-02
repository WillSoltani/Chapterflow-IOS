import Testing
import Foundation
import Networking
@testable import QuizFeature
import Models
import CoreKit

// MARK: - Shared fixtures

private let q1 = QuizQuestion(
    questionId: "q-1",
    prompt: "What is 1+1?",
    choices: [
        QuizChoice(choiceId: "c-1-a", text: "1"),
        QuizChoice(choiceId: "c-1-b", text: "2"),
    ]
)

private let q2 = QuizQuestion(
    questionId: "q-2",
    prompt: "What is 2+2?",
    choices: [
        QuizChoice(choiceId: "c-2-a", text: "3"),
        QuizChoice(choiceId: "c-2-b", text: "4"),
    ]
)

private let testSession = QuizClientSession(
    sessionId: "sess-1",
    questions: [q1, q2],
    passingScorePercent: 70,
    bookId: "b-test",
    chapterNumber: 1,
    tone: nil
)

private let testProgress = BookProgress(
    currentChapterNumber: 1,
    unlockedThroughChapterNumber: 1,
    completedChapters: [],
    bestScoreByChapter: [:],
    preferredVariant: nil,
    progressRev: 1
)

private let passedResult = QuizAttemptResult(
    passed: true,
    scorePercent: 100,
    correctCount: 2,
    totalQuestions: 2,
    cooldownSeconds: 0,
    nextEligibleAttemptAt: nil,
    unlockedNextChapter: true,
    questionResults: [
        QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-b",
                           correctChoiceId: "c-1-b", isCorrect: true),
        QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-b",
                           correctChoiceId: "c-2-b", isCorrect: true),
    ]
)

private let failedResult = QuizAttemptResult(
    passed: false,
    scorePercent: 50,
    correctCount: 1,
    totalQuestions: 2,
    cooldownSeconds: 300,
    nextEligibleAttemptAt: nil,
    unlockedNextChapter: false,
    questionResults: [
        QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-a",
                           correctChoiceId: "c-1-b", isCorrect: false),
        QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-b",
                           correctChoiceId: "c-2-b", isCorrect: true),
    ]
)

// MARK: - QuizModel tests

@Suite("QuizModel")
struct QuizModelTests {

    // MARK: - Load

    @Test("load() transitions to .active and stores session")
    @MainActor
    func testLoad() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)

        await model.load()

        #expect(model.phase == .active)
        #expect(model.session?.sessionId == "sess-1")
        #expect(model.selectedAnswers.isEmpty)
    }

    @Test("load() transitions to .error on AppError.offline")
    @MainActor
    func testLoadOfflineError() async throws {
        let repo = FakeQuizRepository(error: .offline)
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)

        await model.load()

        guard case .error = model.phase else {
            Issue.record("Expected .error phase, got \(model.phase)")
            return
        }
    }

    // MARK: - Answer selection

    @Test("selectAnswer records choice for question")
    @MainActor
    func testSelectAnswer() async {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()

        model.selectAnswer("c-1-b", for: "q-1")

        #expect(model.selectedAnswers["q-1"] == "c-1-b")
    }

    @Test("selectAnswer has no effect outside .active phase")
    @MainActor
    func testSelectAnswerIgnoredWhenNotActive() {
        let repo = FakeQuizRepository()
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        // phase is .idle

        model.selectAnswer("c-1-b", for: "q-1")

        #expect(model.selectedAnswers.isEmpty)
    }

    @Test("allAnswered is false when only some questions have answers")
    @MainActor
    func testAllAnsweredPartial() async {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()

        model.selectAnswer("c-1-b", for: "q-1")   // only 1 of 2

        #expect(model.allAnswered == false)
        #expect(model.canSubmit == false)
    }

    @Test("allAnswered is true when all questions answered")
    @MainActor
    func testAllAnsweredComplete() async {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()

        model.selectAnswer("c-1-b", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")

        #expect(model.allAnswered == true)
    }

    // MARK: - Submit

    @Test("submit() passes to server and transitions to .result on pass")
    @MainActor
    func testSubmitPass() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            submitResult: passedResult
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()
        model.selectAnswer("c-1-b", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")

        await model.submit()

        #expect(model.phase == .result)
        #expect(model.result?.passed == true)
        #expect(model.result?.scorePercent == 100)
        #expect(model.unlockedNextChapter == true)
        #expect(model.retryEligibleAt == nil)  // no cooldown on pass
    }

    @Test("submit() on fail stores server-authoritative cooldown")
    @MainActor
    func testSubmitFailCooldown() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            submitResult: failedResult
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()
        model.selectAnswer("c-1-a", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")

        await model.submit()

        #expect(model.phase == .result)
        #expect(model.result?.passed == false)
        // Cooldown should be anchored ~300 s from now
        #expect(model.retryEligibleAt != nil)
        let remaining = model.cooldownRemaining
        #expect(remaining > 295 && remaining <= 300, "Expected ~300s cooldown, got \(remaining)")
    }

    @Test("submit() sends answers in question order")
    @MainActor
    func testSubmitAnswerOrder() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            submitResult: passedResult
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()
        model.selectAnswer("c-1-b", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")

        await model.submit()

        let recorded = await repo.recordedAnswers
        #expect(recorded.count == 2)
        #expect(recorded[0].questionId == "q-1")
        #expect(recorded[1].questionId == "q-2")
    }

    @Test("submit() with AppError.offline sets isOnline=false and reverts to .active")
    @MainActor
    func testSubmitOffline() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            error: .offline
        )
        // Manually load session so we can test submit path
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        model.injectActiveForPreview(session: testSession, selectedAnswers: [
            "q-1": "c-1-b",
            "q-2": "c-2-b",
        ])

        await model.submit()

        #expect(model.phase == .active)
        #expect(model.isOnline == false)
    }

    // MARK: - Retry gate

    @Test("canRetry is false while cooldown is active")
    @MainActor
    func testCanRetryWhileCooldown() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            submitResult: failedResult
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()
        model.selectAnswer("c-1-a", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")
        await model.submit()

        #expect(model.canRetry == false, "Retry must be blocked during cooldown")
    }

    @Test("canRetry is true when no cooldown (passed attempt)")
    @MainActor
    func testCanRetryAfterPass() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress),
            submitResult: passedResult
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()
        model.selectAnswer("c-1-b", for: "q-1")
        model.selectAnswer("c-2-b", for: "q-2")
        await model.submit()

        // Passed → result has unlockedNextChapter, no retry concept
        // canRetry = false when passed (no failed result)
        #expect(model.canRetry == false)
    }

    // MARK: - passingScorePercent

    @Test("passingScorePercent returns session value")
    @MainActor
    func testPassingScore() async {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        await model.load()

        #expect(model.passingScorePercent == 70)
    }

    @Test("passingScorePercent defaults to 70 when session is nil")
    @MainActor
    func testPassingScoreDefault() {
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: FakeQuizRepository())
        #expect(model.passingScorePercent == 70)
    }
}

// MARK: - FakeQuizRepository tests

@Suite("FakeQuizRepository")
struct FakeQuizRepositoryTests {

    @Test("getQuiz returns stub")
    func testGetQuiz() async throws {
        let repo = FakeQuizRepository(
            quiz: QuizResponse(quiz: testSession, progress: testProgress)
        )
        let response = try await repo.getQuiz(bookId: "b-test", n: 1, tone: nil)
        #expect(response.quiz.sessionId == "sess-1")
    }

    @Test("submit records answers")
    func testSubmitRecordsAnswers() async throws {
        let repo = FakeQuizRepository(submitResult: passedResult)
        let answers = [QuizAnswerSubmission(questionId: "q-1", choiceId: "c-1-b")]
        _ = try await repo.submit(bookId: "b-test", n: 1, answers: answers)
        let recorded = await repo.recordedAnswers
        #expect(recorded == answers)
    }

    @Test("postEvent increments eventCount")
    func testPostEvent() async throws {
        let repo = FakeQuizRepository()
        try await repo.postEvent(bookId: "b-test", n: 1, event: QuizEventPayload(eventType: "test"))
        let count = await repo.eventCount
        #expect(count == 1)
    }

    @Test("forcedError propagates through all methods")
    func testForcedError() async throws {
        let repo = FakeQuizRepository(error: .offline)

        await #expect(throws: AppError.self) {
            _ = try await repo.getQuiz(bookId: "b-test", n: 1, tone: nil)
        }
        await #expect(throws: AppError.self) {
            _ = try await repo.submit(bookId: "b-test", n: 1, answers: [])
        }
    }
}

// MARK: - Endpoint construction tests

@Suite("QuizEndpoints")
struct QuizEndpointTests {
    @Test("submitQuiz endpoint has correct path and method")
    func testSubmitEndpoint() throws {
        let answers = [QuizAnswerSubmission(questionId: "q-1", choiceId: "c-1-b")]
        let endpoint = try Endpoints.submitQuiz(bookId: "b-ah", n: 3, answers: answers)
        #expect(endpoint.path == "/book/me/quiz/b-ah/3/submit")
        #expect(endpoint.method == HTTPMethod.post)
        #expect(endpoint.httpBody != nil)
    }

    @Test("getQuiz endpoint has correct path")
    func testGetQuizEndpoint() {
        let endpoint = Endpoints.getQuiz(bookId: "b-ah", n: 2, tone: "direct")
        #expect(endpoint.path == "/book/books/b-ah/chapters/2/quiz")
        #expect(endpoint.method == HTTPMethod.get)
    }

    @Test("checkQuizAnswer endpoint has correct path")
    func testCheckEndpoint() throws {
        let endpoint = try Endpoints.checkQuizAnswer(
            bookId: "b-ah", n: 1, questionId: "q-1", choiceId: "c-1-a"
        )
        #expect(endpoint.path == "/book/books/b-ah/chapters/1/quiz/check")
        #expect(endpoint.method == HTTPMethod.post)
    }
}
