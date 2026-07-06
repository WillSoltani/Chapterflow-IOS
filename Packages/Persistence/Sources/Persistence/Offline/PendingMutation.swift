import Foundation
import SwiftData

// MARK: - MutationKind

/// The type of an offline write queued in the outbox.
///
/// Every case corresponds to a specific backend endpoint the SyncEngine
/// (P3.4) will call when connectivity is restored. Payloads are replayed
/// verbatim, so they must round-trip losslessly through JSON.
public enum MutationKind: String, Sendable, CaseIterable {
    /// Update the user's current-chapter cursor (`PATCH /book/me/progress/{bookId}`).
    case progressCursor
    /// Submit a quiz to the server for grading (`POST .../quiz/submit`).
    case quizSubmit
    /// Create or update a notebook entry (`POST/PATCH /book/me/notebook`).
    case notebookWrite
    /// Create or update a reader highlight (`POST/PATCH /book/me/notebook`).
    case highlightWrite
    /// Submit an FSRS review grade (`POST /book/me/reviews/{cardId}`).
    case reviewGrade
    /// Create or update a commitment (`POST/PATCH /book/me/commitments`).
    case commitment
    /// Toggle saved/unsaved state for a book (`PATCH /book/me/books/{bookId}/saved`).
    case savedToggle
    /// Log a completed reading session (`POST /book/me/sessions`).
    case readingSession
}

// MARK: - MutationStatus

/// Lifecycle state of a ``PendingMutation`` outbox entry.
public enum MutationStatus: String, Sendable, CaseIterable {
    /// Waiting to be processed.
    case pending
    /// Currently being uploaded by the SyncEngine.
    case inflight
    /// Upload failed; will be retried after backoff.
    case failed
}

// MARK: - PendingMutation

/// A durable offline write queued for replay when connectivity is restored.
///
/// The `payloadJSON` contains all data needed by the SyncEngine to reconstruct
/// and execute the corresponding API call. Payloads must round-trip losslessly —
/// they are replayed verbatim; the SyncEngine never re-derives them from local state.
///
/// **Quiz submissions** are stored here as `quizSubmit` entries. The corresponding
/// ``CachedQuizState`` remains in `.pendingGrading` status until the server response
/// arrives — grading never happens client-side.
@Model
public final class PendingMutation {
    @Attribute(.unique) public var mutationId: String
    public var userId: String
    /// Raw value of ``MutationKind``.
    public var kindRaw: String
    /// JSON-encoded payload — replayed verbatim by the SyncEngine.
    public var payloadJSON: String
    public var createdAt: Date
    public var attemptCount: Int
    public var lastError: String?
    /// Raw value of ``MutationStatus``.
    public var statusRaw: String

    public init(
        mutationId: String = UUID().uuidString,
        userId: String,
        kindRaw: String,
        payloadJSON: String,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil,
        statusRaw: String = MutationStatus.pending.rawValue
    ) {
        self.mutationId = mutationId
        self.userId = userId
        self.kindRaw = kindRaw
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.statusRaw = statusRaw
    }
}

// MARK: - Typed accessors

extension PendingMutation {
    /// Typed mutation kind. `nil` for any future unrecognised kind value.
    public var kind: MutationKind? {
        MutationKind(rawValue: kindRaw)
    }

    /// Typed mutation status. Defaults to `.pending` for unrecognised values.
    public var status: MutationStatus {
        MutationStatus(rawValue: statusRaw) ?? .pending
    }

    /// Convenience factory that encodes a `Codable` payload and queues the mutation.
    public static func make<P: Encodable>(
        userId: String,
        kind: MutationKind,
        payload: P,
        createdAt: Date = Date()
    ) throws -> PendingMutation {
        let data = try JSONEncoder().encode(payload)
        return PendingMutation(
            mutationId: UUID().uuidString,
            userId: userId,
            kindRaw: kind.rawValue,
            payloadJSON: String(bytes: data, encoding: .utf8) ?? "",
            createdAt: createdAt
        )
    }

    /// Decodes the stored payload as the given `Decodable` type.
    public func decodePayload<P: Decodable>(as type: P.Type) throws -> P {
        try JSONDecoder().decode(type, from: Data(payloadJSON.utf8))
    }
}
