import Foundation
import CoreKit
import Networking
import Models

// MARK: - Dispatch extension

extension SyncEngine {

    /// Translates a ``SyncMutationSnapshot`` into an API call.
    ///
    /// Returns without throwing for unknown future `MutationKind` values —
    /// forward-compatible skipping, consistent with RF2 tolerant-enum principle.
    /// Throws `AppError` for network failures; the drain loop handles retry/failure.
    func dispatchMutation(_ snapshot: SyncMutationSnapshot) async throws {
        guard let kind = snapshot.kind else {
            // Unknown future kind: treat as a no-op so the outbox doesn't stall.
            return
        }
        switch kind {
        case .progressCursor:
            try await dispatchProgressCursor(snapshot)
        case .quizSubmit:
            try await dispatchQuizSubmit(snapshot)
        case .notebookWrite:
            try await dispatchNotebookWrite(snapshot)
        case .highlightWrite:
            try await dispatchHighlightWrite(snapshot)
        case .reviewGrade:
            try await dispatchReviewGrade(snapshot)
        case .commitment:
            try await dispatchCommitment(snapshot)
        case .savedToggle:
            try await dispatchSavedToggle(snapshot)
        case .readingSession:
            try await dispatchReadingSession(snapshot)
        }
    }

    // MARK: - Per-kind dispatch

    private func dispatchProgressCursor(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: ProgressCursorPayload.self)
        let endpoint = try Endpoints.patchBookCursor(
            bookId: payload.bookId, chapterId: payload.chapterId
        )
        let _: BookStateResponseEnvelope = try await apiClient.send(endpoint)
    }

    /// Quiz submit with idempotency guard.
    ///
    /// The `sessionId` is the server's idempotency key. A duplicate submit returns
    /// an error code the SyncEngine recognises as "already applied" — it accepts
    /// server truth and deletes the mutation without re-submitting.
    private func dispatchQuizSubmit(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: QuizSubmitPayload.self)

        // Guard against double-submit within a single drain pass.
        // Session IDs are added here and cleared when the tracked drain ends,
        // so a duplicate mutation for the same sessionId is silently skipped.
        let key = payload.sessionId
        guard !activeQuizSessionIds.contains(key) else { return }
        activeQuizSessionIds.insert(key)

        let endpoint = try Endpoints.submitQuiz(
            bookId: payload.bookId,
            chapterNumber: payload.chapterNumber,
            sessionId: payload.sessionId,
            answers: payload.answers
        )

        do {
            let _: QuizAttemptResult = try await apiClient.send(endpoint)
        } catch let error as AppError {
            if Self.isAlreadyApplied(error: error) {
                // Server already processed this quiz session — accept server truth.
                return
            }
            throw error
        }

        // Clear the pendingGrading status from the offline cache.
        try? await store.clearQuizPendingGrading(
            bookId: payload.bookId,
            chapterNumber: payload.chapterNumber,
            userId: snapshot.userId
        )
    }

    private func dispatchNotebookWrite(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: NotebookWritePayload.self)
        if let entryId = payload.entryId {
            // Update existing entry.
            let body = NotebookUpdateRequest(content: payload.content, tags: nil)
            let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
            let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
        } else {
            // Create new entry.
            let request = NotebookEntryRequest(
                bookId: payload.bookId,
                chapterId: payload.chapterId,
                type: payload.type,
                content: payload.content,
                quote: payload.quote,
                color: payload.color
            )
            let endpoint = try Endpoints.postNotebookEntry(request)
            let _: NotebookCreateResponse = try await apiClient.send(endpoint)
        }
    }

    private func dispatchHighlightWrite(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: HighlightWritePayload.self)
        if let entryId = payload.entryId {
            let body = NotebookUpdateRequest(content: nil, tags: nil)
            let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
            let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
        } else {
            let anchor = NotebookEntryRequest.Anchor(
                variantKey: payload.variantKey,
                toneKey: payload.toneKey,
                blockIndex: payload.blockIndex,
                blockType: payload.blockType,
                startChar: payload.startChar,
                endChar: payload.endChar,
                snippet: payload.snippet
            )
            let request = NotebookEntryRequest(
                bookId: payload.bookId,
                chapterId: payload.chapterId,
                type: "highlight",
                content: nil,
                quote: payload.snippet,
                color: payload.color,
                anchor: anchor
            )
            let endpoint = try Endpoints.postNotebookEntry(request)
            let _: NotebookCreateResponse = try await apiClient.send(endpoint)
        }
    }

    private func dispatchReviewGrade(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: ReviewGradePayload.self)
        let endpoint = try Endpoints.gradeReviewCard(cardId: payload.cardId, rating: payload.rating)
        // Response is `{ card: FsrsCard }` — we discard it; repo pulls fresh cards later.
        struct GradeResponse: Decodable, Sendable {
            struct WrappedCard: Decodable, Sendable {
                let cardId: String
            }
            let card: WrappedCard?
        }
        let _: GradeResponse = try await apiClient.send(endpoint)
    }

    private func dispatchCommitment(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: CommitmentPayload.self)
        if let commitmentId = payload.commitmentId {
            // Reflection/outcome update.
            let reflection = payload.reflection ?? ""
            let outcome = payload.outcome ?? ""
            let endpoint = try Endpoints.updateCommitment(
                id: commitmentId,
                reflection: reflection,
                outcomeRawValue: outcome
            )
            struct CommitmentUpdateResponse: Decodable, Sendable {
                struct WrappedCommitment: Decodable, Sendable { let commitmentId: String? }
                let commitment: WrappedCommitment?
            }
            let _: CommitmentUpdateResponse = try await apiClient.send(endpoint)
        } else {
            // Create new commitment.
            guard let ifStatement = payload.ifStatement,
                  let thenStatement = payload.thenStatement,
                  let followUpDays = payload.followUpDays else {
                // Incomplete payload: skip rather than crash.
                return
            }
            let endpoint = try Endpoints.createCommitment(
                bookId: payload.bookId,
                chapterId: payload.chapterId,
                ifStatement: ifStatement,
                thenStatement: thenStatement,
                followUpDays: followUpDays
            )
            struct CommitmentCreateResponse: Decodable, Sendable {
                struct WrappedCommitment: Decodable, Sendable { let commitmentId: String? }
                let commitment: WrappedCommitment?
            }
            let _: CommitmentCreateResponse = try await apiClient.send(endpoint)
        }
    }

    private func dispatchSavedToggle(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: SavedTogglePayload.self)
        let endpoint = try Endpoints.toggleSaved(bookId: payload.bookId, saved: payload.saved)
        let _: SavedBooksResponse = try await apiClient.send(endpoint)
    }

    private func dispatchReadingSession(_ snapshot: SyncMutationSnapshot) async throws {
        let payload = try snapshot.decodePayload(as: ReadingSessionPayload.self)
        let endpoint = try Endpoints.postReadingSessionEvent(
            event: payload.event,
            bookId: payload.bookId,
            chapterId: payload.chapterId,
            sessionId: payload.sessionId
        )
        struct SessionResponse: Decodable, Sendable {
            let sessionId: String?
        }
        let _: SessionResponse = try await apiClient.send(endpoint)
    }

    // MARK: - Idempotency helpers

    /// Server error codes the SyncEngine treats as "mutation already applied".
    ///
    /// On these codes the engine accepts server truth, deletes the mutation from
    /// the outbox, and does NOT retry. This prevents double-submission.
    private static func isAlreadyApplied(error: AppError) -> Bool {
        guard case .server(let code, _, _) = error else { return false }
        let alreadyAppliedCodes: Set<String> = [
            "quiz_already_submitted",
            "session_already_submitted",
            "chapter_already_unlocked",
            "duplicate_request",
            "already_applied",
            "conflict",
        ]
        return alreadyAppliedCodes.contains(code)
    }
}

// MARK: - Response stubs (private to dispatch)

/// Minimal wrapper to satisfy `Decodable` for `PATCH /book/me/books/{bookId}/state`.
private struct BookStateResponseEnvelope: Decodable, Sendable {
    let state: WrappedState?
    struct WrappedState: Decodable, Sendable {
        let currentChapterId: String?
    }
}
