import Foundation
import CoreKit
import Networking
import Models
import Persistence

enum MutationDispatchOutcome: Sendable, Equatable {
    case applied
    /// Reserved for endpoint-specific server proof; no local duplicate may produce this outcome.
    case alreadyApplied
    case quarantined(MutationQuarantineReason)
}

enum MutationQuarantineReason: String, Sendable, Equatable {
    case unknownKind = "unknown_kind"
    case malformedPayload = "malformed_payload"
    case missingRequiredField = "missing_required_field"
    case ambiguousLocalDuplicate = "ambiguous_local_duplicate"
    case unsupportedPayloadVersion = "unsupported_payload_version"

    var safeCode: String { "sync.quarantine.\(rawValue)" }
}

private struct StoredPayloadDecodeFailure: Error, Sendable {}

// MARK: - Dispatch extension

extension SyncEngine {

    /// Translates a ``SyncMutationSnapshot`` into an API call.
    ///
    /// Unknown or unsafe local data returns an explicit quarantine outcome.
    /// Network, authentication, and server failures continue to throw.
    func dispatchMutation(_ snapshot: SyncMutationSnapshot) async throws -> MutationDispatchOutcome {
        guard let kind = snapshot.kind else {
            return .quarantined(.unknownKind)
        }
        do {
            switch kind {
            case .progressCursor:
                return try await dispatchProgressCursor(snapshot)
            case .quizSubmit:
                // Legacy quiz payloads predate the attemptNumber contract and
                // cannot be replayed safely. Quarantine before decoding or transport.
                return .quarantined(.unsupportedPayloadVersion)
            case .notebookWrite:
                return try await dispatchNotebookWrite(snapshot)
            case .highlightWrite:
                return try await dispatchHighlightWrite(snapshot)
            case .notebookDelete:
                return try await dispatchNotebookDelete(snapshot)
            case .reviewGrade:
                return try await dispatchReviewGrade(snapshot)
            case .commitment:
                return try await dispatchCommitment(snapshot)
            case .savedToggle:
                return try await dispatchSavedToggle(snapshot)
            case .readingSession:
                return try await dispatchReadingSession(snapshot)
            }
        } catch is StoredPayloadDecodeFailure {
            return .quarantined(.malformedPayload)
        }
    }

    // MARK: - Per-kind dispatch

    private func dispatchProgressCursor(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: ProgressCursorPayload.self)
        let endpoint = try Endpoints.patchBookCursor(
            bookId: payload.bookId, chapterId: payload.chapterId
        )
        let _: BookStateResponseEnvelope = try await apiClient.send(endpoint)
        return .applied
    }

    private func dispatchNotebookWrite(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: NotebookWritePayload.self)
        if let entryId = payload.entryId {
            // Update existing entry.
            let body = NotebookUpdateRequest(content: payload.content, tags: nil)
            let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
            let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
        } else {
            if let localAnnotationID = payload.localAnnotationId {
                guard !localAnnotationID.isEmpty else {
                    return .quarantined(.missingRequiredField)
                }
                let state = try await store.annotationCreateReconciliationState(
                    localAnnotationId: localAnnotationID
                )
                if state == .reconciled {
                    return .applied
                }
            }
            // Create new entry.
            let anchor = payload.anchor.map {
                NotebookEntryRequest.Anchor(
                    variantKey: $0.variantKey,
                    toneKey: $0.toneKey,
                    blockIndex: $0.blockIndex,
                    blockType: $0.blockType,
                    startChar: $0.startChar,
                    endChar: $0.endChar,
                    snippet: $0.snippet
                )
            }
            let request = NotebookEntryRequest(
                bookId: payload.bookId,
                chapterId: payload.chapterId,
                type: payload.type,
                content: payload.content,
                quote: payload.quote,
                color: payload.color,
                anchor: anchor
            )
            let endpoint = try Endpoints.postNotebookEntry(request)
            let response: NotebookCreateResponse = try await apiClient.send(endpoint)
            try Task.checkCancellation()
            if let localAnnotationID = payload.localAnnotationId {
                try await store.reconcileAnnotationCreate(
                    localAnnotationId: localAnnotationID,
                    serverEntryId: response.entryId,
                    userId: snapshot.userId
                )
            }
        }
        return .applied
    }

    private func dispatchHighlightWrite(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: HighlightWritePayload.self)
        if let entryId = payload.entryId {
            let body = NotebookUpdateRequest(content: nil, tags: nil)
            let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
            let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
        } else {
            if let localAnnotationID = payload.localAnnotationId {
                guard !localAnnotationID.isEmpty else {
                    return .quarantined(.missingRequiredField)
                }
                let state = try await store.annotationCreateReconciliationState(
                    localAnnotationId: localAnnotationID
                )
                if state == .reconciled {
                    return .applied
                }
            }
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
            let response: NotebookCreateResponse = try await apiClient.send(endpoint)
            try Task.checkCancellation()
            if let localAnnotationID = payload.localAnnotationId {
                try await store.reconcileAnnotationCreate(
                    localAnnotationId: localAnnotationID,
                    serverEntryId: response.entryId,
                    userId: snapshot.userId
                )
            }
        }
        return .applied
    }

    private func dispatchNotebookDelete(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: NotebookDeletePayload.self)
        guard !payload.localAnnotationId.isEmpty, !payload.serverEntryId.isEmpty else {
            return .quarantined(.missingRequiredField)
        }
        let endpoint = Endpoints.deleteNotebookEntry(entryId: payload.serverEntryId)
        let _: NotebookDeleteResponse = try await apiClient.send(endpoint)
        try Task.checkCancellation()
        try await store.removeConfirmedAnnotationDelete(
            localAnnotationId: payload.localAnnotationId,
            serverEntryId: payload.serverEntryId
        )
        return .applied
    }

    private func dispatchReviewGrade(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: ReviewGradePayload.self)
        let endpoint = try Endpoints.gradeReviewCard(cardId: payload.cardId, rating: payload.rating)
        // Response is `{ card: FsrsCard }` — we discard it; repo pulls fresh cards later.
        struct GradeResponse: Decodable, Sendable {
            struct WrappedCard: Decodable, Sendable {
                let cardId: String
            }
            let card: WrappedCard?
        }
        let _: GradeResponse = try await apiClient.send(endpoint)
        return .applied
    }

    private func dispatchCommitment(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: CommitmentPayload.self)
        if let commitmentId = payload.commitmentId {
            // Reflection/outcome update.
            guard let reflection = payload.reflection,
                  let outcome = payload.outcome else {
                return .quarantined(.missingRequiredField)
            }
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
                return .quarantined(.missingRequiredField)
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
        return .applied
    }

    private func dispatchSavedToggle(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: SavedTogglePayload.self)
        let endpoint = try Endpoints.toggleSaved(bookId: payload.bookId, saved: payload.saved)
        let _: SavedBooksResponse = try await apiClient.send(endpoint)
        return .applied
    }

    private func dispatchReadingSession(
        _ snapshot: SyncMutationSnapshot
    ) async throws -> MutationDispatchOutcome {
        let payload = try decodeStoredPayload(snapshot, as: ReadingSessionPayload.self)
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
        return .applied
    }

    // MARK: - Stored-payload decoding

    private func decodeStoredPayload<Payload: Decodable>(
        _ snapshot: SyncMutationSnapshot,
        as type: Payload.Type
    ) throws -> Payload {
        do {
            return try snapshot.decodePayload(as: type)
        } catch {
            throw StoredPayloadDecodeFailure()
        }
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
