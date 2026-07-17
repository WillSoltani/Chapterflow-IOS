import Testing
import Foundation
import SwiftData
import Networking
@testable import QuizFeature
import Models
import CoreKit
import Persistence
import os

// MARK: - Shared fixtures

private func question(_ id: String, choices: [String]) -> QuizQuestion {
    QuizQuestion(questionId: id, prompt: "Prompt for \(id)", choices: choices.map { QuizChoice(choiceId: $0, text: $0) })
}

private let q1 = question("q-1", choices: ["c-1-a", "c-1-b"])
private let q2 = question("q-2", choices: ["c-2-a", "c-2-b"])

private func session(
    id: String? = "sess-1", attempt: Int? = 2, status: QuizSessionStatus? = .ready,
    questions: [QuizQuestion] = [q1, q2], book: String = "b-test", chapter: Int = 1,
    tone: ToneKey? = nil
) -> QuizClientSession {
    QuizClientSession(
        sessionId: id, attemptNumber: attempt, nextAttemptNumber: status == .passed ? nil : attempt,
        status: status, questions: questions, passingScorePercent: 70,
        bookId: book, chapterNumber: chapter, tone: tone
    )
}

private let testSession = session()
private let testProgress = BookProgress(
    currentChapterNumber: 1, unlockedThroughChapterNumber: 1, completedChapters: [],
    bestScoreByChapter: [:], preferredVariant: nil, progressRev: 1
)
private let passedResult = QuizAttemptResult(
    passed: true, scorePercent: 100, correctCount: 2, totalQuestions: 2, cooldownSeconds: 0,
    nextEligibleAttemptAt: nil, unlockedNextChapter: true,
    questionResults: [
        QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-b", correctChoiceId: "c-1-b", isCorrect: true),
        QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-b", correctChoiceId: "c-2-b", isCorrect: true),
    ]
)
private let failedResult = QuizAttemptResult(
    passed: false, scorePercent: 50, correctCount: 1, totalQuestions: 2, cooldownSeconds: 300,
    nextEligibleAttemptAt: nil, unlockedNextChapter: false,
    questionResults: [
        QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-a", correctChoiceId: "c-1-b", isCorrect: false),
        QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-b", correctChoiceId: "c-2-b", isCorrect: true),
    ]
)

@MainActor
private func loadedModel(_ repository: FakeQuizRepository) async -> QuizModel {
    let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repository)
    await model.load()
    return model
}

@MainActor
private func answerAll(_ model: QuizModel, firstChoice: String = "c-1-b") {
    model.selectAnswer(firstChoice, for: "q-1")
    model.selectAnswer("c-2-b", for: "q-2")
}

// MARK: - QuizModel tests

@Suite("QuizModel")
struct QuizModelTests {
    @Test("load() transitions to .active and stores session")
    @MainActor
    func testLoad() async {
        let model = await loadedModel(FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress)))
        #expect(model.phase == .active)
        #expect(model.session?.sessionId == "sess-1")
        #expect(model.selectedAnswers.isEmpty)
        #expect(model.passingScorePercent == 70)
    }
    @Test("load() transitions to .error on AppError.offline")
    @MainActor
    func testLoadOfflineError() async {
        let model = await loadedModel(FakeQuizRepository(error: .offline))
        guard case .error = model.phase else {
            Issue.record("Expected .error phase, got \(model.phase)")
            return
        }
    }
    @Test("selectAnswer records choice for question")
    @MainActor
    func testSelectAnswer() async {
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress))
        let model = await loadedModel(repo)
        model.selectAnswer("c-1-b", for: "q-1")
        await model.waitForDraftSave()
        #expect(model.selectedAnswers["q-1"] == "c-1-b")
        #expect(await repo.savedDraft == ["q-1": "c-1-b"])
        #expect(await repo.draftSaveCount == 1)
    }
    @Test("selectAnswer has no effect outside .active phase")
    @MainActor
    func testSelectAnswerIgnoredWhenNotActive() {
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: FakeQuizRepository())
        model.selectAnswer("c-1-b", for: "q-1")
        #expect(model.selectedAnswers.isEmpty)
    }
    @Test("allAnswered and canSubmit track answer completeness")
    @MainActor
    func testAnswerCompleteness() async {
        let model = await loadedModel(FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress)))
        model.selectAnswer("c-1-b", for: "q-1")
        #expect(model.allAnswered == false)
        #expect(model.canSubmit == false)
        model.selectAnswer("c-2-b", for: "q-2")
        #expect(model.allAnswered == true)
    }
    @Test("submit() uses question order and transitions to the authoritative pass result")
    @MainActor
    func testSubmitPassAndAnswerOrder() async {
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress), submitResult: passedResult)
        let model = await loadedModel(repo)
        answerAll(model)
        await model.submit()
        #expect(model.phase == .result)
        #expect(model.result?.passed == true)
        #expect(model.result?.scorePercent == 100)
        #expect(model.unlockedNextChapter == true)
        #expect(model.retryEligibleAt == nil)
        #expect(model.canRetry == false)
        let recorded = await repo.recordedResponses
        #expect(recorded.count == 2)
        #expect(recorded.map(\.questionId) == ["q-1", "q-2"])
        #expect(recorded.map(\.selectedChoiceId) == ["c-1-b", "c-2-b"])
        #expect(await repo.recordedAttemptNumber == 2)
    }
    @Test("submit() on fail stores server-authoritative cooldown and blocks retry")
    @MainActor
    func testSubmitFailCooldown() async {
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress), submitResult: failedResult)
        let model = await loadedModel(repo)
        answerAll(model, firstChoice: "c-1-a")
        await model.submit()
        #expect(model.phase == .result)
        #expect(model.result?.passed == false)
        #expect(model.retryEligibleAt != nil)
        let remaining = model.cooldownRemaining
        #expect(remaining > 295 && remaining <= 300, "Expected ~300s cooldown, got \(remaining)")
        #expect(model.canRetry == false)
    }
    @Test("offline submit confirms the draft without transport or local grading")
    @MainActor
    func testSubmitOffline() async {
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress), offlineSubmit: true)
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        model.injectActiveForPreview(
            session: testSession, selectedAnswers: ["q-1": "c-1-b", "q-2": "c-2-b"], isOnline: false
        )
        #expect(model.allAnswered == true)
        #expect(model.canSubmit == true)
        await model.submit()
        #expect(model.phase == .active)
        #expect(model.draftState == .savedRequiresConnection)
        #expect(await repo.networkSubmitCount == 0)
        #expect((await repo.recordedResponses).count == 2)
        #expect(await repo.savedDraft == ["q-1": "c-1-b", "q-2": "c-2-b"])
        #expect(model.result == nil)
        #expect(model.retryEligibleAt == nil)
        #expect(model.unlockedNextChapter == false)
    }
    @Test("draft save failure never claims success")
    @MainActor
    func testDraftSaveFailure() async {
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress), offlineSubmit: true)
        await repo.setDraftError(.storageUnavailable)
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: repo)
        model.injectActiveForPreview(
            session: testSession, selectedAnswers: ["q-1": "c-1-b", "q-2": "c-2-b"], isOnline: false
        )
        await model.submit()
        guard case .failed = model.draftState else {
            Issue.record("Expected failed draft state")
            return
        }
        #expect(model.phase == .active)
        #expect(await repo.networkSubmitCount == 0)
    }
    @Test("relaunch restores matching answers and connectivity never auto-submits")
    @MainActor
    func testRestoreAndNoAutomaticSubmit() async {
        let restored = ["q-1": "c-1-b", "q-2": "c-2-b"]
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress), restoredAnswers: restored)
        let model = await loadedModel(repo)
        model.injectActiveForPreview(session: testSession, selectedAnswers: restored, isOnline: true)
        #expect(model.selectedAnswers == restored)
        #expect(model.draftState == .saved)
        #expect(await repo.networkSubmitCount == 0)
    }
    @Test("missing attempt identity disables submit and requires refresh")
    @MainActor
    func testMissingAttemptRequiresRefresh() {
        let model = QuizModel(bookId: "b-test", chapterNumber: 1, repository: FakeQuizRepository())
        model.injectActiveForPreview(session: session(id: "legacy", attempt: nil), selectedAnswers: [
            "q-1": "c-1-b", "q-2": "c-2-b",
        ])
        #expect(!model.canSubmit)
        #expect(model.requiresSessionRefresh)
    }
    @Test("offline UI copy says saved locally and requires explicit online submit")
    @MainActor
    func testOfflineDraftCopy() {
        #expect(QuizView.savedDraftOfflineMessage.contains("saved on this device"))
        #expect(QuizView.savedDraftOfflineMessage.contains("Connect"))
        #expect(QuizView.savedDraftOfflineMessage.contains("Submit Quiz"))
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
        let repo = FakeQuizRepository(quiz: QuizResponse(quiz: testSession, progress: testProgress))
        let response = try await repo.getQuiz(bookId: "b-test", n: 1, tone: nil)
        #expect(response.quiz.sessionId == "sess-1")
    }
    @Test("submit records attempt identity and canonical responses")
    func testSubmitRecordsResponses() async throws {
        let repo = FakeQuizRepository(submitResult: passedResult)
        let responses = [
            QuizAnswerSubmission(questionId: "q-1", selectedChoiceId: "c-1-b"),
            QuizAnswerSubmission(questionId: "q-2", selectedChoiceId: "c-2-b"),
        ]
        _ = try await repo.submitAttempt(bookId: "b-test", n: 1, session: testSession, responses: responses)
        #expect(await repo.recordedResponses == responses)
        #expect(await repo.recordedAttemptNumber == 2)
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
            _ = try await repo.submitAttempt(bookId: "b-test", n: 1, session: testSession, responses: [])
        }
    }
}

// MARK: - Endpoint construction tests

@Suite("QuizEndpoints")
struct QuizEndpointTests {
    @Test("submitQuiz encodes only canonical attemptNumber and ordered responses")
    func testSubmitEndpoint() throws {
        let responses = [
            QuizAnswerSubmission(questionId: "q-1", selectedChoiceId: "c-1-b"),
            QuizAnswerSubmission(questionId: "q-2", selectedChoiceId: "c-2-b"),
        ]
        let endpoint = try Endpoints.submitQuiz(bookId: "b-ah", n: 3, attemptNumber: 7, responses: responses)
        #expect(endpoint.path == "/book/me/quiz/b-ah/3/submit")
        #expect(endpoint.method == HTTPMethod.post)
        #expect(endpoint.reliabilityPolicy.retryPolicy == .none)

        let body = try #require(endpoint.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(root.keys) == ["attemptNumber", "responses"])
        #expect(root["attemptNumber"] as? Int == 7)
        let encodedResponses = try #require(root["responses"] as? [[String: Any]])
        #expect(encodedResponses.count == 2)
        #expect(encodedResponses.map { $0["questionId"] as? String } == ["q-1", "q-2"])
        #expect(encodedResponses.map { $0["selectedChoiceId"] as? String } == ["c-1-b", "c-2-b"])
        #expect(encodedResponses.allSatisfy { Set($0.keys) == ["questionId", "selectedChoiceId"] })
        #expect(root["answers"] == nil)
        #expect(root["sessionId"] == nil)
    }

    @Test("getQuiz endpoint has correct path")
    func testGetQuizEndpoint() {
        let endpoint = Endpoints.getQuiz(bookId: "b-ah", n: 2, tone: "direct")
        #expect(endpoint.path == "/book/books/b-ah/chapters/2/quiz")
        #expect(endpoint.method == HTTPMethod.get)
    }

    @Test("checkQuizAnswer endpoint has correct path")
    func testCheckEndpoint() throws {
        let endpoint = try Endpoints.checkQuizAnswer(bookId: "b-ah", n: 1, questionId: "q-1", choiceId: "c-1-a")
        #expect(endpoint.path == "/book/books/b-ah/chapters/1/quiz/check")
        #expect(endpoint.method == HTTPMethod.post)
    }
}

// MARK: - Durable draft integration

@Suite("Live quiz draft repository", .serialized)
struct LiveQuizDraftRepositoryTests {
    @Test("A and B read only their own cached quiz row")
    @MainActor
    func cachedQuizReadsAreAccountIsolated() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let context = container.mainContext
        context.insert(try CachedQuizState.from(
            makeSession(sessionID: "session-a"), userId: "account-a", bookId: "shared-book", chapterNumber: 1,
            selectedAnswers: ["question-session-a": "choice-1"]
        ))
        context.insert(try CachedQuizState.from(
            makeSession(sessionID: "session-b"), userId: "account-b", bookId: "shared-book", chapterNumber: 1,
            selectedAnswers: ["question-session-b": "choice-2"]
        ))
        context.insert(try CachedQuizState.from(
            makeSession(sessionID: "session-anon", chapterNumber: 2),
            userId: "anon", bookId: "shared-book", chapterNumber: 2
        ))
        try context.save()
        let client = MockAPIClient()
        await client.setDefault(.failure(.notFound))
        let accountA = makeRepository(client: client, container: container)
        let accountB = makeRepository(client: client, container: container, accountID: "account-b")
        let aQuiz = try await accountA.loadQuiz(bookId: "shared-book", n: 1, tone: nil)
        let bQuiz = try await accountB.loadQuiz(bookId: "shared-book", n: 1, tone: nil)
        #expect(aQuiz.response.quiz.sessionId == "session-a")
        #expect(bQuiz.response.quiz.sessionId == "session-b")
        #expect(aQuiz.selectedAnswers == ["question-session-a": "choice-1"])
        #expect(bQuiz.selectedAnswers == ["question-session-b": "choice-2"])
        await #expect(throws: (any Error).self) {
            try await accountA.getQuiz(bookId: "shared-book", n: 2, tone: nil)
        }
    }
    @Test("same-attempt changed questions do not erase unresolved draft bytes")
    @MainActor
    func sameAttemptQuestionMismatchPreservesDraft() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let context = container.mainContext
        let cachedRow = try CachedQuizState.from(
            makeSession(sessionID: "cached", attemptNumber: 2),
            userId: "account-a", bookId: "shared-book", chapterNumber: 1,
            selectedAnswers: ["question-cached": "choice-2"], status: .draftPendingOnline
        )
        context.insert(cachedRow)
        try context.save()
        let originalJSON = cachedRow.dataJSON
        let refreshedSession = makeSession(sessionID: "changed", attemptNumber: 2)
        let client = MockAPIClient()
        try await client.setStub(
            QuizResponse(quiz: refreshedSession, progress: makeProgress()),
            for: "/book/books/shared-book/chapters/1/quiz"
        )
        let repository = makeRepository(client: client, container: container)
        let loaded = try await repository.loadQuiz(bookId: "shared-book", n: 1, tone: nil)
        #expect(loaded.response.quiz.sessionId == "changed")
        #expect(loaded.selectedAnswers.isEmpty)
        let stored = try #require(try context.fetch(FetchDescriptor<CachedQuizState>()).first)
        #expect(stored.dataJSON == originalJSON)
        #expect(try stored.toDocument().selectedAnswers == ["question-cached": "choice-2"])
        #expect(stored.status == .draftPendingOnline)
    }
    @Test("offline draft survives relaunch and submits only after an explicit reconnect action")
    @MainActor
    func hermeticDraftRelaunchAndExplicitSubmit() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let client = MockAPIClient()
        let connectivity = QuizDraftConnectivityFlag(false)
        let session = makeSession(sessionID: "attempt-one")
        let answer = ["question-attempt-one": "choice-2"]
        let firstRepository = makeRepository(client: client, container: container) { connectivity.value }
        let firstModel = QuizModel(bookId: "shared-book", chapterNumber: 1, repository: firstRepository)
        firstModel.injectActiveForPreview(session: session, isOnline: false)
        firstModel.selectAnswer("choice-2", for: "question-attempt-one")
        await firstModel.waitForDraftSave()
        await firstModel.submit()
        #expect(firstModel.draftState == .savedRequiresConnection)
        #expect((await client.recordedEndpoints).isEmpty)
        let firstContext = ModelContext(container)
        #expect(try firstContext.fetchCount(FetchDescriptor<PendingMutation>()) == 0)
        let relaunchedRepository = makeRepository(client: client, container: container) { connectivity.value }
        let relaunchedModel = QuizModel(bookId: "shared-book", chapterNumber: 1, repository: relaunchedRepository)
        await relaunchedModel.load()
        #expect(relaunchedModel.selectedAnswers == answer)
        #expect(relaunchedModel.draftState == .saved)
        connectivity.set(true)
        await Task.yield()
        #expect((await client.recordedEndpoints).isEmpty)
        let submitPath = "/book/me/quiz/shared-book/1/submit"
        try await client.setStub(makePassedResult(), for: submitPath)
        await relaunchedModel.submit()
        #expect(relaunchedModel.phase == .result)
        #expect(relaunchedModel.result?.passed == true)
        let calls = await client.recordedEndpoints
        #expect(calls.filter { $0.path == submitPath }.count == 1)
        let finalContext = ModelContext(container)
        let rows = try finalContext.fetch(FetchDescriptor<CachedQuizState>())
        let row = try #require(rows.first { $0.userId == "account-a" })
        #expect(try row.toDocument().selectedAnswers.isEmpty)
        #expect(row.status == .ready)
        #expect(try finalContext.fetchCount(FetchDescriptor<PendingMutation>()) == 0)
    }
    @Test("ordinary submit failure retains the exact draft")
    @MainActor
    func ordinaryFailureRetainsDraft() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let client = MockAPIClient()
        let session = makeSession(sessionID: "ordinary-failure", attemptNumber: 4)
        let responses = responses(for: session, selectedChoiceID: "choice-1")
        let submitPath = "/book/me/quiz/shared-book/1/submit"
        await client.setStub(
            .failure(.server(code: "server_error", message: "Failed", requestId: nil)),
            for: submitPath
        )
        let repository = makeRepository(client: client, container: container)
        await #expect(throws: AppError.self) {
            try await repository.submitAttempt(bookId: "shared-book", n: 1, session: session, responses: responses)
        }
        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<CachedQuizState>()).first)
        #expect(try row.toDocument().selectedAnswers == ["question-ordinary-failure": "choice-1"])
        #expect(row.status == .draftPendingOnline)
        #expect((await client.recordedEndpoints).filter { $0.path == submitPath }.count == 1)
    }

    @Test("stale submit refreshes once, never resubmits, and drops answers for an advanced attempt")
    @MainActor
    func staleRefreshDoesNotResubmit() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let client = MockAPIClient()
        let oldSession = makeSession(sessionID: "old", attemptNumber: 2)
        let freshSession = makeSession(sessionID: "fresh", attemptNumber: 3)
        let submitPath = "/book/me/quiz/shared-book/1/submit"
        let getPath = "/book/books/shared-book/chapters/1/quiz"
        await client.setStub(
            .failure(.server(code: "quiz_session_stale", message: "Refresh required", requestId: nil)),
            for: submitPath
        )
        try await client.setStub(QuizResponse(quiz: freshSession, progress: makeProgress()), for: getPath)
        let repository = makeRepository(client: client, container: container)
        let outcome = try await repository.submitAttempt(
            bookId: "shared-book", n: 1, session: oldSession,
            responses: responses(for: oldSession, selectedChoiceID: "choice-2")
        )
        guard case .refreshedAfterStale(let loaded) = outcome else {
            Issue.record("Expected refreshed stale outcome")
            return
        }
        #expect(loaded.response.quiz.attemptNumber == 3)
        #expect(loaded.selectedAnswers.isEmpty)
        let calls = await client.recordedEndpoints
        #expect(calls.filter { $0.path == submitPath }.count == 1)
        #expect(calls.filter { $0.path == getPath }.count == 1)
        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<CachedQuizState>()).first)
        #expect(try row.toDocument().session.attemptNumber == 3)
        #expect(try row.toDocument().selectedAnswers.isEmpty)
    }

    private func makeSession(
        sessionID: String,
        chapterNumber: Int = 1,
        attemptNumber: Int = 1,
        status: QuizSessionStatus = .ready
    ) -> QuizClientSession {
        session(
            id: sessionID, attempt: attemptNumber, status: status,
            questions: [question("question-\(sessionID)", choices: ["choice-1", "choice-2"])],
            book: "shared-book", chapter: chapterNumber
        )
    }
    private func makeRepository(
        client: MockAPIClient,
        container: ModelContainer,
        accountID: String = "account-a",
        connectivity: @escaping @Sendable () -> Bool = { true }
    ) -> LiveQuizRepository {
        LiveQuizRepository(
            client: client, container: container, reachability: ReachabilityService(),
            accountID: accountID, connectivityCheck: connectivity
        )
    }
    private func responses(for session: QuizClientSession, selectedChoiceID: String) -> [QuizAnswerSubmission] {
        session.questions.map {
            QuizAnswerSubmission(questionId: $0.questionId, selectedChoiceId: selectedChoiceID)
        }
    }
    private func makeProgress() -> BookProgress { testProgress }
    private func makePassedResult() -> QuizAttemptResult {
        QuizAttemptResult(
            passed: true, scorePercent: 100, correctCount: 1, totalQuestions: 1, cooldownSeconds: 0,
            nextEligibleAttemptAt: nil, unlockedNextChapter: true,
            questionResults: [
                QuizQuestionResult(
                    questionId: "question-attempt-one", selectedChoiceId: "choice-2",
                    correctChoiceId: "choice-2", isCorrect: true
                ),
            ]
        )
    }
}

private final class QuizDraftConnectivityFlag: @unchecked Sendable {
    private let storage: OSAllocatedUnfairLock<Bool>

    init(_ initialValue: Bool) {
        storage = OSAllocatedUnfairLock(initialState: initialValue)
    }

    var value: Bool {
        storage.withLock { $0 }
    }

    func set(_ value: Bool) {
        storage.withLock { $0 = value }
    }
}

@Suite("Cached quiz draft compatibility")
struct CachedQuizDraftCompatibilityTests {
    @Test("current quiz session decodes attempt identity and tolerant status")
    func currentSessionAttemptIdentity() throws {
        let json = #"{"attemptNumber":3,"nextAttemptNumber":3,"status":"future_state","questions":[{"questionId":"q-1","prompt":"Prompt","choices":[{"choiceId":"c-1","text":"One"}]}]}"#
        let session = try JSONDecoder().decode(QuizClientSession.self, from: Data(json.utf8))
        #expect(session.attemptNumber == 3)
        #expect(session.nextAttemptNumber == 3)
        #expect(session.status == .unknown("future_state"))
    }
    @Test("missing attempt number remains displayable without an inferred default")
    func missingAttemptNumberIsTolerated() throws {
        let json = #"{"status":"ready","questions":[{"questionId":"q-1","prompt":"Prompt","choices":[{"choiceId":"c-1","text":"One"}]}]}"#
        let session = try JSONDecoder().decode(QuizClientSession.self, from: Data(json.utf8))
        #expect(session.attemptNumber == nil)
        #expect(session.questions.count == 1)
    }

    @Test("legacy bare-session cache decodes with an empty draft")
    func legacyBareSession() throws {
        let session = makeSession()
        let data = try JSONEncoder().encode(session)
        let json = try #require(String(bytes: data, encoding: .utf8))
        let row = CachedQuizState(
            rowId: "u:b:1", userId: "u", bookId: "b", chapterNumber: 1,
            sessionId: session.sessionId, dataJSON: json
        )
        let document = try row.toDocument()
        #expect(document.version == CachedQuizDocument.currentVersion)
        #expect(document.session.sessionId == session.sessionId)
        #expect(document.selectedAnswers.isEmpty)
    }

    @Test("versioned draft round-trips selected answers")
    func versionedDraftRoundTrip() throws {
        let row = try CachedQuizState.from(
            makeSession(), userId: "u", bookId: "b", chapterNumber: 1,
            selectedAnswers: ["q-1": "c-2"], status: .draftPendingOnline
        )
        let document = try row.toDocument()
        #expect(document.version == 1)
        #expect(document.session.attemptNumber == 2)
        #expect(document.selectedAnswers == ["q-1": "c-2"])
        #expect(row.status == .draftPendingOnline)
    }

    @Test("malformed document fails without manufacturing a session")
    func malformedDocumentFailsSafely() {
        let row = CachedQuizState(
            rowId: "u:b:1", userId: "u", bookId: "b", chapterNumber: 1,
            dataJSON: #"{"version":1,"session":"not-a-session"}"#
        )
        #expect(throws: (any Error).self) { try row.toDocument() }
    }

    @Test("different attempt or question assignment never restores answers", arguments: [(3, "q-1"), (2, "q-new")])
    func mismatchedSessionDoesNotRestoreAnswers(attemptNumber: Int, questionID: String) throws {
        let document = try CachedQuizDocument(session: makeSession(), selectedAnswers: ["q-1": "c-1"])
        #expect(document.answers(matching: makeSession(attemptNumber: attemptNumber, questionID: questionID)).isEmpty)
    }

    @Test("invalid question and choice IDs cannot enter a draft")
    func invalidSelectionsAreRejected() {
        #expect(throws: CachedQuizDocumentError.self) {
            try CachedQuizDocument(session: makeSession(), selectedAnswers: ["q-1": "not-a-choice"])
        }
    }
    private func makeSession(attemptNumber: Int = 2, questionID: String = "q-1") -> QuizClientSession {
        session(
            id: nil, attempt: attemptNumber,
            questions: [question(questionID, choices: ["c-1", "c-2"])], book: "b", tone: .direct
        )
    }
}
