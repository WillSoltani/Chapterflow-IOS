import SwiftData
import Testing
import os
import CoreKit
import Models
import Networking
import Persistence
@testable import QuizFeature

@Suite("LiveQuizRepository identity", .serialized)
struct LiveQuizRepositoryIdentityTests {
    @Test("A and B read only their own cached quiz row")
    @MainActor
    func cachedQuizReadsAreAccountIsolated() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let context = container.mainContext
        let accountASession = makeSession(sessionID: "session-a")
        let accountBSession = makeSession(sessionID: "session-b")
        let legacyFallbackSession = makeSession(sessionID: "session-anon", chapterNumber: 2)
        context.insert(try CachedQuizState.from(
            accountASession,
            userId: "account-a",
            bookId: "shared-book",
            chapterNumber: 1,
            selectedAnswers: ["question-session-a": "choice-1"]
        ))
        context.insert(try CachedQuizState.from(
            accountBSession,
            userId: "account-b",
            bookId: "shared-book",
            chapterNumber: 1,
            selectedAnswers: ["question-session-b": "choice-2"]
        ))
        context.insert(try CachedQuizState.from(
            legacyFallbackSession,
            userId: "anon",
            bookId: "shared-book",
            chapterNumber: 2
        ))
        try context.save()

        let client = MockAPIClient()
        await client.setDefault(.failure(.notFound))
        let reachability = ReachabilityService()
        let accountA = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-a"
        )
        let accountB = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-b"
        )

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
        let cachedSession = makeSession(sessionID: "cached", attemptNumber: 2)
        let cachedRow = try CachedQuizState.from(
            cachedSession,
            userId: "account-a",
            bookId: "shared-book",
            chapterNumber: 1,
            selectedAnswers: ["question-cached": "choice-2"],
            status: .draftPendingOnline
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
        let repository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: ReachabilityService(),
            accountID: "account-a",
            connectivityCheck: { true }
        )

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
        let connectivity = ConnectivityFlag(false)
        let reachability = ReachabilityService()
        let session = makeSession(sessionID: "attempt-one")
        let answer = ["question-attempt-one": "choice-2"]

        let firstRepository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-a",
            connectivityCheck: { connectivity.value }
        )
        let firstModel = QuizModel(
            bookId: "shared-book",
            chapterNumber: 1,
            repository: firstRepository
        )
        firstModel.injectActiveForPreview(session: session, isOnline: false)
        firstModel.selectAnswer("choice-2", for: "question-attempt-one")
        await firstModel.waitForDraftSave()
        await firstModel.submit()

        #expect(firstModel.draftState == .savedRequiresConnection)
        #expect((await client.recordedEndpoints).isEmpty)
        let firstContext = ModelContext(container)
        #expect(try firstContext.fetchCount(FetchDescriptor<PendingMutation>()) == 0)

        let relaunchedRepository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-a",
            connectivityCheck: { connectivity.value }
        )
        let relaunchedModel = QuizModel(
            bookId: "shared-book",
            chapterNumber: 1,
            repository: relaunchedRepository
        )
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
        let reachability = ReachabilityService()
        let session = makeSession(sessionID: "ordinary-failure", attemptNumber: 4)
        let responses = responses(for: session, selectedChoiceID: "choice-1")
        let submitPath = "/book/me/quiz/shared-book/1/submit"
        await client.setStub(
            .failure(.server(code: "server_error", message: "Failed", requestId: nil)),
            for: submitPath
        )
        let repository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-a",
            connectivityCheck: { true }
        )

        await #expect(throws: AppError.self) {
            try await repository.submitAttempt(
                bookId: "shared-book",
                n: 1,
                session: session,
                responses: responses
            )
        }

        let context = ModelContext(container)
        let row = try #require(try context.fetch(FetchDescriptor<CachedQuizState>()).first)
        #expect(try row.toDocument().selectedAnswers == [
            "question-ordinary-failure": "choice-1",
        ])
        #expect(row.status == .draftPendingOnline)
        #expect((await client.recordedEndpoints).filter { $0.path == submitPath }.count == 1)
    }

    @Test("stale submit refreshes once, never resubmits, and drops answers for an advanced attempt")
    @MainActor
    func staleRefreshDoesNotResubmit() async throws {
        let container = try PersistenceController(storage: .inMemory).container
        let client = MockAPIClient()
        let reachability = ReachabilityService()
        let oldSession = makeSession(sessionID: "old", attemptNumber: 2)
        let freshSession = makeSession(sessionID: "fresh", attemptNumber: 3)
        let submitPath = "/book/me/quiz/shared-book/1/submit"
        let getPath = "/book/books/shared-book/chapters/1/quiz"
        await client.setStub(
            .failure(.server(
                code: "quiz_session_stale",
                message: "Refresh required",
                requestId: nil
            )),
            for: submitPath
        )
        try await client.setStub(
            QuizResponse(quiz: freshSession, progress: makeProgress()),
            for: getPath
        )
        let repository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: "account-a",
            connectivityCheck: { true }
        )

        let outcome = try await repository.submitAttempt(
            bookId: "shared-book",
            n: 1,
            session: oldSession,
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
        QuizClientSession(
            sessionId: sessionID,
            attemptNumber: attemptNumber,
            nextAttemptNumber: status == .passed ? nil : attemptNumber,
            status: status,
            questions: [
                QuizQuestion(
                    questionId: "question-\(sessionID)",
                    prompt: "Prompt for \(sessionID)",
                    choices: [
                        QuizChoice(choiceId: "choice-1", text: "One"),
                        QuizChoice(choiceId: "choice-2", text: "Two"),
                    ]
                ),
            ],
            passingScorePercent: 70,
            bookId: "shared-book",
            chapterNumber: chapterNumber,
            tone: nil
        )
    }

    private func responses(
        for session: QuizClientSession,
        selectedChoiceID: String
    ) -> [QuizAnswerSubmission] {
        session.questions.map {
            QuizAnswerSubmission(
                questionId: $0.questionId,
                selectedChoiceId: selectedChoiceID
            )
        }
    }

    private func makeProgress() -> BookProgress {
        BookProgress(
            currentChapterNumber: 1,
            unlockedThroughChapterNumber: 1,
            completedChapters: [],
            bestScoreByChapter: [:],
            preferredVariant: nil,
            progressRev: 1
        )
    }

    private func makePassedResult() -> QuizAttemptResult {
        QuizAttemptResult(
            passed: true,
            scorePercent: 100,
            correctCount: 1,
            totalQuestions: 1,
            cooldownSeconds: 0,
            nextEligibleAttemptAt: nil,
            unlockedNextChapter: true,
            questionResults: [
                QuizQuestionResult(
                    questionId: "question-attempt-one",
                    selectedChoiceId: "choice-2",
                    correctChoiceId: "choice-2",
                    isCorrect: true
                ),
            ]
        )
    }
}

private final class ConnectivityFlag: @unchecked Sendable {
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
