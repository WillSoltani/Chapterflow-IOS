import Foundation
import SwiftData
import Models
import Networking
import Persistence
import CoreKit

/// Production ``QuizRepository`` with account-scoped, local-only quiz drafts.
///
/// Drafts never enter the sync outbox. An offline submit action confirms the
/// durable draft and returns without transport; only a later explicit online
/// action may send the server-issued attempt number for grading.
public actor LiveQuizRepository: QuizRepository {

    private struct CacheTarget {
        let row: CachedQuizState?
        let bookId: String
        let chapterNumber: Int
    }

    private let client: any APIClientProtocol
    private let container: ModelContainer?
    private let accountID: String
    private let workPermit: SessionWorkPermit
    private let isConnected: @Sendable () -> Bool

    public init(
        client: any APIClientProtocol,
        container: ModelContainer? = nil,
        reachability: ReachabilityService,
        accountID: String,
        workPermit: SessionWorkPermit = SessionWorkPermit(),
        connectivityCheck: (@Sendable () -> Bool)? = nil
    ) {
        self.client = client
        self.container = container
        self.accountID = accountID
        self.workPermit = workPermit
        self.isConnected = connectivityCheck ?? { reachability.isConnectedSync }
    }

    // MARK: - Quiz loading

    public func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        try await loadQuiz(bookId: bookId, n: n, tone: tone).response
    }

    public func loadQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> LoadedQuiz {
        let ticket = try workPermit.begin()
        let cached = try? loadCachedQuiz(bookId: bookId, chapterNumber: n)

        guard isConnected() else {
            guard let cached else { throw AppError.offline }
            return cached
        }

        do {
            return try await fetchAndCacheQuiz(
                bookId: bookId,
                n: n,
                tone: tone,
                ticket: ticket
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    private func loadCachedQuiz(bookId: String, chapterNumber: Int) throws -> LoadedQuiz? {
        guard let container else { return nil }
        let context = ModelContext(container)
        guard let row = try cachedRow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            in: context
        ) else {
            return nil
        }
        let document = try row.toDocument()
        let response = QuizResponse(
            quiz: document.session,
            progress: .placeholder(chapterNumber: chapterNumber)
        )
        return LoadedQuiz(
            response: response,
            selectedAnswers: document.answers(matching: document.session)
        )
    }

    private func fetchAndCacheQuiz(
        bookId: String,
        n: Int,
        tone: ToneKey?,
        ticket: UInt64
    ) async throws -> LoadedQuiz {
        let response: QuizResponse = try await client.send(
            Endpoints.getQuiz(bookId: bookId, n: n, tone: tone?.rawValue)
        )
        let answers: [String: String]
        if let container {
            answers = try workPermit.commit(ticket) {
                try cacheQuizSession(
                    response.quiz,
                    bookId: bookId,
                    chapterNumber: n,
                    in: container
                )
            }
        } else {
            try workPermit.validate(ticket)
            answers = [:]
        }
        return LoadedQuiz(response: response, selectedAnswers: answers)
    }

    /// Stores a fresh server session while carrying forward only a matching draft.
    @discardableResult
    private func cacheQuizSession(
        _ session: QuizClientSession,
        bookId: String,
        chapterNumber: Int,
        in container: ModelContainer
    ) throws -> [String: String] {
        let context = ModelContext(container)
        let existing = try cachedRow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            in: context
        )
        let existingDocument = try? existing?.toDocument()
        let preservedAnswers = existingDocument?.answers(matching: session) ?? [:]
        if let existingDocument,
           !existingDocument.selectedAnswers.isEmpty,
           preservedAnswers.isEmpty,
           let draftAttempt = existingDocument.session.attemptNumber,
           !Self.serverSupersedesDraft(
               draftAttempt: draftAttempt,
               refreshedSession: session
           ) {
            // Show the refreshed session without applying mismatched answers,
            // while preserving unresolved draft bytes until server truth advances.
            return [:]
        }
        try writeDocument(
            session: session,
            selectedAnswers: preservedAnswers,
            status: preservedAnswers.isEmpty ? .ready : .draftPendingOnline,
            target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
            in: context
        )
        return preservedAnswers
    }

    // MARK: - Drafts and submit

    public func saveDraft(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        selectedAnswers: [String: String]
    ) async throws {
        let ticket = try workPermit.begin()
        try Task.checkCancellation()
        try workPermit.commit(ticket) {
            try persistDraft(
                bookId: bookId,
                chapterNumber: n,
                session: session,
                selectedAnswers: selectedAnswers
            )
        }
    }

    public func submitAttempt(
        bookId: String,
        n: Int,
        session: QuizClientSession,
        responses: [QuizAnswerSubmission]
    ) async throws -> QuizSubmissionOutcome {
        guard let attemptNumber = session.attemptNumber, attemptNumber > 0,
              session.status == .ready,
              session.nextAttemptNumber == attemptNumber else {
            throw QuizDraftError.missingAttemptNumber
        }
        guard Self.responsesAreComplete(responses, for: session) else {
            throw QuizDraftError.invalidResponses
        }

        let ticket = try workPermit.begin()
        let selectedAnswers = Dictionary(
            uniqueKeysWithValues: responses.map {
                ($0.questionId, $0.selectedChoiceId)
            }
        )
        try workPermit.commit(ticket) {
            try persistDraft(
                bookId: bookId,
                chapterNumber: n,
                session: session,
                selectedAnswers: selectedAnswers
            )
        }

        guard isConnected() else {
            return .draftSavedRequiresConnection
        }

        let endpoint = try Endpoints.submitQuiz(
            bookId: bookId,
            n: n,
            attemptNumber: attemptNumber,
            responses: responses
        )
        do {
            let result: QuizAttemptResult = try await client.send(endpoint)
            let draftCleared = (try? workPermit.commit(ticket) {
                try clearDraft(bookId: bookId, chapterNumber: n, session: session)
            }) != nil
            return .graded(result, draftCleared: draftCleared)
        } catch let error as AppError where error.code == "quiz_session_stale" {
            let refreshed: QuizResponse = try await client.send(
                Endpoints.getQuiz(bookId: bookId, n: n, tone: session.tone?.rawValue)
            )
            let restored = try workPermit.commit(ticket) {
                try reconcileStaleDraft(
                    submittedAttempt: attemptNumber,
                    refreshedSession: refreshed.quiz,
                    bookId: bookId,
                    chapterNumber: n
                )
            }
            return .refreshedAfterStale(
                LoadedQuiz(response: refreshed, selectedAnswers: restored)
            )
        }
    }

    private func persistDraft(
        bookId: String,
        chapterNumber: Int,
        session: QuizClientSession,
        selectedAnswers: [String: String]
    ) throws {
        guard let container else { throw QuizDraftError.storageUnavailable }
        let context = ModelContext(container)
        let existing = try cachedRow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            in: context
        )
        do {
            try writeDocument(
                session: session,
                selectedAnswers: selectedAnswers,
                status: selectedAnswers.isEmpty ? .ready : .draftPendingOnline,
                target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
                in: context
            )
        } catch is CachedQuizDocumentError {
            throw QuizDraftError.invalidResponses
        }
    }

    private func clearDraft(
        bookId: String,
        chapterNumber: Int,
        session: QuizClientSession
    ) throws {
        guard let container else { throw QuizDraftError.storageUnavailable }
        let context = ModelContext(container)
        let existing = try cachedRow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            in: context
        )
        try writeDocument(
            session: session,
            selectedAnswers: [:],
            status: .ready,
            target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
            in: context
        )
    }

    /// Reconciles one stale response without ever resubmitting or rebasing answers.
    private func reconcileStaleDraft(
        submittedAttempt: Int,
        refreshedSession: QuizClientSession,
        bookId: String,
        chapterNumber: Int
    ) throws -> [String: String] {
        guard let container else { throw QuizDraftError.storageUnavailable }
        let context = ModelContext(container)
        let existing = try cachedRow(
            bookId: bookId,
            chapterNumber: chapterNumber,
            in: context
        )

        if Self.serverSupersedesDraft(
            draftAttempt: submittedAttempt,
            refreshedSession: refreshedSession
        ) {
            try writeDocument(
                session: refreshedSession,
                selectedAnswers: [:],
                status: .ready,
                target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
                in: context
            )
            return [:]
        }

        guard let document = try? existing?.toDocument() else {
            try writeDocument(
                session: refreshedSession,
                selectedAnswers: [:],
                status: .ready,
                target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
                in: context
            )
            return [:]
        }
        let matchingAnswers = document.answers(matching: refreshedSession)
        guard !matchingAnswers.isEmpty || document.selectedAnswers.isEmpty else {
            // Preserve the unresolved old document, but never apply it to this session.
            return [:]
        }
        try writeDocument(
            session: refreshedSession,
            selectedAnswers: matchingAnswers,
            status: matchingAnswers.isEmpty ? .ready : .draftPendingOnline,
            target: CacheTarget(row: existing, bookId: bookId, chapterNumber: chapterNumber),
            in: context
        )
        return matchingAnswers
    }

    private func writeDocument(
        session: QuizClientSession,
        selectedAnswers: [String: String],
        status: QuizCacheStatus,
        target: CacheTarget,
        in context: ModelContext
    ) throws {
        let document = try CachedQuizDocument(
            session: session,
            selectedAnswers: selectedAnswers
        )
        let data = try JSONEncoder().encode(document)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw CachedQuizDocumentError.invalidEncoding
        }

        if let existing = target.row {
            existing.sessionId = session.sessionId
            existing.dataJSON = json
            existing.statusRaw = status.rawValue
            existing.cachedAt = Date()
        } else {
            context.insert(CachedQuizState(
                rowId: CachedQuizState.makeRowId(
                    userId: accountID,
                    bookId: target.bookId,
                    chapterNumber: target.chapterNumber
                ),
                userId: accountID,
                bookId: target.bookId,
                chapterNumber: target.chapterNumber,
                sessionId: session.sessionId,
                dataJSON: json,
                statusRaw: status.rawValue
            ))
        }
        try context.save()
    }

    private func cachedRow(
        bookId: String,
        chapterNumber: Int,
        in context: ModelContext
    ) throws -> CachedQuizState? {
        let rowID = CachedQuizState.makeRowId(
            userId: accountID,
            bookId: bookId,
            chapterNumber: chapterNumber
        )
        let descriptor = FetchDescriptor<CachedQuizState>(
            predicate: #Predicate { $0.rowId == rowID }
        )
        return try context.fetch(descriptor).first
    }

    private static func responsesAreComplete(
        _ responses: [QuizAnswerSubmission],
        for session: QuizClientSession
    ) -> Bool {
        guard responses.count == session.questions.count else { return false }
        return zip(session.questions, responses).allSatisfy { question, response in
            question.questionId == response.questionId
                && question.choices.contains { $0.choiceId == response.selectedChoiceId }
        }
    }

    private static func serverSupersedesDraft(
        draftAttempt: Int,
        refreshedSession: QuizClientSession
    ) -> Bool {
        switch refreshedSession.status {
        case .passed:
            return true
        case .ready:
            return (refreshedSession.attemptNumber ?? 0) > draftAttempt
        case .cooldown:
            return (refreshedSession.attemptNumber ?? 0) >= draftAttempt
        case .unknown, nil:
            return false
        }
    }

    // MARK: - Check / event (online-only)

    public func check(
        bookId: String,
        n: Int,
        questionId: String,
        choiceId: String
    ) async throws -> QuizCheckResult {
        let endpoint = try Endpoints.checkQuizAnswer(
            bookId: bookId,
            n: n,
            questionId: questionId,
            choiceId: choiceId
        )
        return try await client.send(endpoint)
    }

    public func postEvent(bookId: String, n: Int, event: QuizEventPayload) async throws {
        guard isConnected() else { return }
        let endpoint = try Endpoints.postQuizEvent(bookId: bookId, n: n, event: event)
        let _: QuizEventAck = try await client.send(endpoint)
    }
}

// MARK: - BookProgress placeholder

private extension BookProgress {
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
