import Foundation
import SwiftData
import Models
import Networking
import Persistence
import CoreKit

/// Production ``QuizRepository`` — offline-capable via SwiftData cache and
/// a ``PendingMutation`` outbox for submissions taken without connectivity.
///
/// **Offline contract**
/// - `getQuiz`: serves ``CachedQuizState`` when offline; throws ``AppError/offline``
///   when neither cache nor network is available.
/// - `submit`: when offline, encodes the answers as a ``MutationKind/quizSubmit``
///   outbox entry, marks the cached quiz as `.pendingGrading`, and throws
///   ``QuizSubmissionError/pendingGrading`` so the caller can show the waiting UI.
///   **Answers are never graded locally.**
public actor LiveQuizRepository: QuizRepository {

    private let client: any APIClientProtocol
    private let container: ModelContainer?
    private let reachability: ReachabilityService
    private let userId: @Sendable () -> String?

    public init(
        client: any APIClientProtocol,
        container: ModelContainer? = nil,
        reachability: ReachabilityService,
        userId: @Sendable @escaping () -> String?
    ) {
        self.client = client
        self.container = container
        self.reachability = reachability
        self.userId = userId
    }

    // MARK: - Quiz loading

    public func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        // Cache-first: serve any cached ready/pending session immediately.
        if let cached = try loadCachedQuiz(bookId: bookId, chapterNumber: n) {
            // Background refresh when online (picks up any server-side changes).
            if reachability.isConnectedSync {
                Task { try? await fetchAndCacheQuiz(bookId: bookId, n: n, tone: tone) }
            }
            return cached
        }
        guard reachability.isConnectedSync else { throw AppError.offline }
        return try await fetchAndCacheQuiz(bookId: bookId, n: n, tone: tone)
    }

    private func loadCachedQuiz(bookId: String, chapterNumber: Int) throws -> QuizResponse? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<CachedQuizState>(
            predicate: #Predicate { $0.bookId == bookId && $0.chapterNumber == chapterNumber }
        )
        guard let row = try ctx.fetch(descriptor).first else { return nil }
        let session = try row.toDomain()
        return QuizResponse(quiz: session, progress: .placeholder(chapterNumber: chapterNumber))
    }

    @discardableResult
    private func fetchAndCacheQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        let response: QuizResponse = try await client.send(
            Endpoints.getQuiz(bookId: bookId, n: n, tone: tone?.rawValue)
        )
        if let container {
            try cacheQuizSession(response.quiz, bookId: bookId, chapterNumber: n, in: container)
        }
        return response
    }

    private func cacheQuizSession(
        _ session: QuizClientSession,
        bookId: String,
        chapterNumber: Int,
        in container: ModelContainer
    ) throws {
        let ctx = ModelContext(container)
        let uid = userId() ?? "anon"
        let rowId = CachedQuizState.makeRowId(userId: uid, bookId: bookId, chapterNumber: chapterNumber)
        let descriptor = FetchDescriptor<CachedQuizState>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        let data = try JSONEncoder().encode(session)
        let json = String(bytes: data, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(descriptor).first {
            // Don't downgrade a pendingGrading row back to ready.
            if existing.status == .ready {
                existing.dataJSON = json
                existing.cachedAt = Date()
            }
        } else {
            let row = try CachedQuizState.from(
                session,
                userId: uid,
                bookId: bookId,
                chapterNumber: chapterNumber,
                status: .ready
            )
            ctx.insert(row)
        }
        try ctx.save()
    }

    // MARK: - Submit

    public func submit(bookId: String, n: Int, answers: [QuizAnswerSubmission]) async throws -> QuizAttemptResult {
        if !reachability.isConnectedSync {
            try enqueueOfflineSubmit(bookId: bookId, chapterNumber: n, answers: answers)
            throw QuizSubmissionError.pendingGrading
        }
        let endpoint = try Endpoints.submitQuiz(bookId: bookId, n: n, answers: answers)
        return try await client.send(endpoint)
    }

    private func enqueueOfflineSubmit(
        bookId: String,
        chapterNumber: Int,
        answers: [QuizAnswerSubmission]
    ) throws {
        guard let container else { return }
        let ctx = ModelContext(container)
        let uid = userId() ?? "anon"

        struct SubmitPayload: Codable {
            let bookId: String
            let chapterNumber: Int
            let answers: [QuizAnswerSubmission]
        }
        let payload = SubmitPayload(bookId: bookId, chapterNumber: chapterNumber, answers: answers)
        let mutation = try PendingMutation.make(
            userId: uid,
            kind: .quizSubmit,
            payload: payload
        )
        ctx.insert(mutation)

        // Mark the cached quiz session as pending grading.
        let rowId = CachedQuizState.makeRowId(userId: uid, bookId: bookId, chapterNumber: chapterNumber)
        let descriptor = FetchDescriptor<CachedQuizState>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        if let cached = try ctx.fetch(descriptor).first {
            cached.statusRaw = QuizCacheStatus.pendingGrading.rawValue
        }
        try ctx.save()
    }

    // MARK: - Check / event (online-only; no offline fallback needed)

    public func check(bookId: String, n: Int, questionId: String, choiceId: String) async throws -> QuizCheckResult {
        let endpoint = try Endpoints.checkQuizAnswer(
            bookId: bookId, n: n,
            questionId: questionId, choiceId: choiceId
        )
        return try await client.send(endpoint)
    }

    public func postEvent(bookId: String, n: Int, event: QuizEventPayload) async throws {
        guard reachability.isConnectedSync else { return }
        let endpoint = try Endpoints.postQuizEvent(bookId: bookId, n: n, event: event)
        let _: QuizEventAck = try await client.send(endpoint)
    }
}

// MARK: - BookProgress placeholder

private extension BookProgress {
    /// Minimal placeholder used when serving a quiz from cache without live progress.
    static func placeholder(chapterNumber: Int) -> BookProgress {
        BookProgress(
            currentChapterNumber: chapterNumber,
            unlockedThroughChapterNumber: chapterNumber,
            completedChapters: [],
            bestScoreByChapter: [:],
            preferredVariant: nil,
            progressRev: nil
        )
    }
}
