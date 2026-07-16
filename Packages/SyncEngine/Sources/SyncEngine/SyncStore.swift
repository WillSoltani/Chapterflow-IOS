import Foundation
import SwiftData
import Persistence
import Models

// MARK: - SyncMutationSnapshot

/// A `Sendable` snapshot of a ``PendingMutation``, safe to pass across actor boundaries.
///
/// ``PendingMutation`` is a SwiftData `@Model` and is therefore not `Sendable`.
/// This value type captures the fields the SyncEngine needs so the actor can
/// read payload data without violating SwiftData isolation.
struct SyncMutationSnapshot: Sendable {
    let mutationId: String
    let userId: String
    let kindRaw: String
    let payloadJSON: String
    let attemptCount: Int

    init(from mutation: PendingMutation) {
        mutationId = mutation.mutationId
        userId = mutation.userId
        kindRaw = mutation.kindRaw
        payloadJSON = mutation.payloadJSON
        attemptCount = mutation.attemptCount
    }

    var kind: MutationKind? { MutationKind(rawValue: kindRaw) }

    /// Decodes the stored payload JSON into a `Decodable` type.
    func decodePayload<P: Decodable>(as type: P.Type) throws -> P {
        try JSONDecoder().decode(type, from: Data(payloadJSON.utf8))
    }
}

// MARK: - SyncStore

/// A dedicated `@ModelActor` for the SyncEngine's SwiftData operations.
///
/// All methods run on a private background context so they never block the main
/// actor. They return `Sendable` value types (snapshots, counts) that the
/// ``SyncEngine`` actor can consume without isolation violations.
@ModelActor
actor SyncStore {

    // MARK: - Fetch

    /// Returns all pending mutations for a user, ordered by creation time (FIFO).
    ///
    /// Mutations in `inflight` state (left over from a previous interrupted drain)
    /// are reset to `pending` so the engine replays them.
    func fetchPendingMutations(userId: String) throws -> [SyncMutationSnapshot] {
        // Reset any stuck inflight mutations from a previous crashed drain.
        let inflightDesc = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == userId && $0.statusRaw == "inflight" }
        )
        let inflight = try modelContext.fetch(inflightDesc)
        for mutation in inflight {
            mutation.statusRaw = MutationStatus.pending.rawValue
        }
        if !inflight.isEmpty {
            try modelContext.save()
        }

        let quarantinedStatus = MutationStatus.quarantined.rawValue
        var descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate {
                $0.userId == userId && $0.statusRaw != quarantinedStatus
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 200
        let results = try modelContext.fetch(descriptor)
        return results.map { SyncMutationSnapshot(from: $0) }
    }

    /// Counts all retained mutations for a user (including failed and quarantined entries).
    func countPendingMutations(userId: String) throws -> Int {
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Status updates

    /// Marks a mutation as `inflight` so it isn't double-drained on rapid retriggers.
    func markInflight(mutationId: String) throws {
        guard let mutation = try fetchMutation(mutationId: mutationId) else { return }
        mutation.statusRaw = MutationStatus.inflight.rawValue
        try modelContext.save()
    }

    /// Records a failure using a closed, privacy-safe code.
    func markFailed(mutationId: String, failureCode: MutationFailureCode) throws {
        guard let mutation = try fetchMutation(mutationId: mutationId) else { return }
        mutation.statusRaw = MutationStatus.failed.rawValue
        mutation.lastError = failureCode.rawValue
        mutation.attemptCount += 1
        try modelContext.save()
    }

    /// Retains an unsafe-to-dispatch mutation with a closed quarantine reason.
    func markQuarantined(
        mutationId: String,
        reason: MutationQuarantineReason
    ) throws {
        guard let mutation = try fetchMutation(mutationId: mutationId) else { return }
        mutation.statusRaw = MutationStatus.quarantined.rawValue
        mutation.lastError = reason.safeCode
        try modelContext.save()
    }

    /// Removes a successfully synced (or idempotently accepted) mutation from the outbox.
    @discardableResult
    func deleteMutation(mutationId: String) throws -> Bool {
        try Task.checkCancellation()
        guard let mutation = try fetchMutation(mutationId: mutationId) else { return false }
        try Task.checkCancellation()
        modelContext.delete(mutation)
        try modelContext.save()
        return true
    }

    // MARK: - Post-sync state updates

    /// After a successful quiz submit, clears the `pendingGrading` flag so the
    /// QuizFeature repository knows the result is now available from the server.
    ///
    /// The CachedQuizState is reset to `.ready` rather than deleted so the UI
    /// can immediately offer the quiz again (the repo will pull fresh progress).
    func clearQuizPendingGrading(bookId: String, chapterNumber: Int, userId: String) throws {
        let rowId = CachedQuizState.makeRowId(
            userId: userId, bookId: bookId, chapterNumber: chapterNumber
        )
        let descriptor = FetchDescriptor<CachedQuizState>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        guard let state = try modelContext.fetch(descriptor).first else { return }
        guard state.statusRaw == QuizCacheStatus.pendingGrading.rawValue else { return }
        state.statusRaw = QuizCacheStatus.ready.rawValue
        try modelContext.save()
    }

    // MARK: - Private

    private func fetchMutation(mutationId: String) throws -> PendingMutation? {
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.mutationId == mutationId }
        )
        return try modelContext.fetch(descriptor).first
    }
}
