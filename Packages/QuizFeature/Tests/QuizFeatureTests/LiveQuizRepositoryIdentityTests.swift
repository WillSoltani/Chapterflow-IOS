import SwiftData
import Testing
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
            chapterNumber: 1
        ))
        context.insert(try CachedQuizState.from(
            accountBSession,
            userId: "account-b",
            bookId: "shared-book",
            chapterNumber: 1
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

        let aQuiz = try await accountA.getQuiz(bookId: "shared-book", n: 1, tone: nil)
        let bQuiz = try await accountB.getQuiz(bookId: "shared-book", n: 1, tone: nil)
        #expect(aQuiz.quiz.sessionId == "session-a")
        #expect(bQuiz.quiz.sessionId == "session-b")

        await #expect(throws: (any Error).self) {
            try await accountA.getQuiz(bookId: "shared-book", n: 2, tone: nil)
        }
    }

    private func makeSession(
        sessionID: String,
        chapterNumber: Int = 1
    ) -> QuizClientSession {
        QuizClientSession(
            sessionId: sessionID,
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
}
