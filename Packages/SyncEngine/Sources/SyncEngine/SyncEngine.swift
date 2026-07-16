import Foundation
import Network
import SwiftData
import CoreKit
import Networking
import Persistence
import os

enum MutationFailureCode: String, Sendable, Equatable {
    case authentication = "sync.failure.authentication"
    case verifierUnavailable = "sync.failure.verifier_unavailable"
    case rateLimited = "sync.failure.rate_limited"
    case forbidden = "sync.failure.forbidden"
    case offline = "sync.failure.offline"
    case invalidInput = "sync.failure.invalid_input"
    case notFound = "sync.failure.not_found"
    case server = "sync.failure.server"
    case responseDecoding = "sync.failure.response_decoding"
    case unknown = "sync.failure.unknown"

    init(error: Error) {
        guard let appError = error as? AppError else {
            self = .unknown
            return
        }
        switch appError {
        case .unauthenticated, .reauthRequired:
            self = .authentication
        case .verifierUnavailable:
            self = .verifierUnavailable
        case .rateLimited:
            self = .rateLimited
        case .forbidden:
            self = .forbidden
        case .offline:
            self = .offline
        case .invalidInput:
            self = .invalidInput
        case .notFound:
            self = .notFound
        case .server:
            self = .server
        case .decoding:
            self = .responseDecoding
        }
    }
}

// MARK: - SyncEngine

/// Drains the offline write outbox when connectivity is restored.
///
/// **Responsibilities:**
/// - Drain ``PendingMutation`` entries IN ORDER on reconnect, app foreground,
///   or BGAppRefresh, with exponential backoff retry.
/// - Accept server truth for gating fields: the client NEVER pushes unlocks or
///   completions; it pushes cursor, notes, highlights, grades, and sessions and
///   PULLS gating truth from the server.
/// - Idempotent quiz replay: a quiz taken offline stays "pending grading" until
///   its submit returns an authoritative applied outcome.
/// - Expose observable ``SyncStatus`` for a subtle UI indicator.
///
/// Start the engine after authentication by calling ``start(userId:)``.
/// Stop it on sign-out with ``stop()``.
public actor SyncEngine {

    // MARK: - Public interface

    /// Observable status for the sync-status UI indicator.
    ///
    /// Updated on `@MainActor` by the drain loop; bind directly in SwiftUI.
    public nonisolated let status: SyncStatus

    // MARK: - Dependencies

    let apiClient: any APIClientProtocol
    let store: SyncStore

    // MARK: - State

    /// In-memory ownership of quiz session IDs within a single drain pass.
    /// The same row may retry; a distinct row with the same key is ambiguous.
    var activeQuizSessionOwners: [String: String] = [:]

    /// The current drain task, if any.
    private var drainTask: Task<Void, Never>?
    private var drainTaskID: UUID?

    /// The network-monitor task that fires ``triggerDrain(userId:)`` on path changes.
    private var monitorTask: Task<Void, Never>?
    private var monitorTaskID: UUID?

    /// Invalidates callbacks from an earlier start/stop lifecycle.
    private var lifecycleID = UUID()

    /// `false` while stopped or while a replacement lifecycle is joining old work.
    private var acceptsDrainTriggers = true

    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "SyncEngine")

    // MARK: - Init

    public init(apiClient: any APIClientProtocol, container: ModelContainer) {
        self.apiClient = apiClient
        self.store = SyncStore(modelContainer: container)
        self.status = SyncStatus()
    }

    // MARK: - Lifecycle

    /// Starts the sync engine for the given user.
    ///
    /// Begins monitoring network connectivity and triggers an initial drain
    /// in case mutations accumulated while offline.
    public func start(userId: String) async {
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        acceptsDrainTriggers = false

        await cancelAndJoinMonitor()
        await cancelAndJoinDrain()

        guard self.lifecycleID == lifecycleID else { return }
        acceptsDrainTriggers = true
        startNetworkMonitor(userId: userId, lifecycleID: lifecycleID)
        // Trigger an eager drain in case mutations accumulated while offline.
        triggerDrain(userId: userId, lifecycleID: lifecycleID)
    }

    /// Stops the sync engine (call on sign-out or app termination).
    ///
    /// Cancellation is followed by a join so a resumed account scope cannot
    /// overlap an earlier drain or network monitor.
    public func stop() async {
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        acceptsDrainTriggers = false

        let monitor = monitorTask
        let monitorID = monitorTaskID
        let drain = drainTask
        let drainID = drainTaskID
        monitor?.cancel()
        drain?.cancel()

        await monitor?.value
        await drain?.value

        if let monitorID {
            finishMonitor(id: monitorID)
        }
        if let drainID {
            finishDrain(id: drainID)
        }
        if self.lifecycleID == lifecycleID {
            activeQuizSessionOwners.removeAll()
        }
    }

    // MARK: - Drain trigger

    /// Schedules a drain pass if one is not already running.
    ///
    /// Idempotent: calling while a drain is in progress is a no-op.
    /// The engine serialises drain passes — a new pass starts only after the
    /// previous one completes (or is cancelled).
    public func triggerDrain(userId: String) {
        triggerDrain(userId: userId, lifecycleID: lifecycleID)
    }

    /// Cancels any in-flight drain and performs a full drain pass to completion.
    ///
    /// Unlike ``triggerDrain(userId:)`` (which returns immediately), this method
    /// awaits the drain loop. Use it from BGTask handlers so the task is marked
    /// complete only when the outbox is truly empty.
    public func drainAndWait(userId: String) async {
        let lifecycleID = lifecycleID
        guard acceptsDrainTriggers else { return }

        await cancelAndJoinDrain()

        guard acceptsDrainTriggers,
              self.lifecycleID == lifecycleID,
              !Task.isCancelled else { return }
        triggerDrain(userId: userId, lifecycleID: lifecycleID)
        guard let drainTask else { return }

        await withTaskCancellationHandler {
            await drainTask.value
        } onCancel: {
            drainTask.cancel()
        }
    }

    private func triggerDrain(userId: String, lifecycleID: UUID) {
        guard acceptsDrainTriggers,
              self.lifecycleID == lifecycleID,
              drainTask == nil else { return }

        let taskID = UUID()
        drainTaskID = taskID
        drainTask = Task { [weak self] in
            guard let self else { return }
            await self.drain(userId: userId)
            await self.finishDrain(id: taskID)
        }
    }

    private func cancelAndJoinDrain() async {
        guard let drainTask else { return }
        let taskID = drainTaskID
        drainTask.cancel()
        await drainTask.value
        if let taskID {
            finishDrain(id: taskID)
        }
    }

    private func finishDrain(id: UUID) {
        guard drainTaskID == id else { return }
        drainTask = nil
        drainTaskID = nil
        // Reset local duplicate ownership so the next drain pass starts fresh.
        activeQuizSessionOwners.removeAll()
    }

    /// Waits for the currently tracked drain without changing its lifecycle.
    /// Internal so deterministic tests can prove teardown/resume ordering.
    func waitForCurrentDrain() async {
        let drainTask = drainTask
        await drainTask?.value
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor(userId: String, lifecycleID: UUID) {
        let monitor = NWPathMonitor()
        let taskID = UUID()
        monitorTaskID = taskID
        monitorTask = Task { [weak self] in
            for await path in Self.networkPathStream(monitor: monitor) where path.status == .satisfied {
                guard !Task.isCancelled else { break }
                await self?.triggerDrain(userId: userId, lifecycleID: lifecycleID)
            }
            await self?.finishMonitor(id: taskID)
        }
    }

    private func cancelAndJoinMonitor() async {
        guard let monitorTask else { return }
        let taskID = monitorTaskID
        monitorTask.cancel()
        await monitorTask.value
        if let taskID {
            finishMonitor(id: taskID)
        }
    }

    private func finishMonitor(id: UUID) {
        guard monitorTaskID == id else { return }
        monitorTask = nil
        monitorTaskID = nil
    }

    /// Wraps `NWPathMonitor` in an `AsyncStream` so we can use `for await`.
    private static func networkPathStream(monitor: NWPathMonitor) -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in continuation.yield(path) }
            monitor.start(queue: DispatchQueue(label: "com.chapterflow.sync.monitor"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }

    // MARK: - Drain loop

    private func drain(userId: String) async {
        let snapshots: [SyncMutationSnapshot]
        do {
            try Task.checkCancellation()
            snapshots = try await store.fetchPendingMutations(userId: userId)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            let failureCode = MutationFailureCode(error: error)
            logger.error(
                "SyncEngine: failed to fetch pending mutations: \(failureCode.rawValue, privacy: .public)"
            )
            await updateStatus(phase: .error, pendingCount: 0, error: failureCode.rawValue)
            return
        }

        let retainedCount = (try? await store.countPendingMutations(userId: userId))
            ?? snapshots.count
        guard !Task.isCancelled else { return }
        guard !snapshots.isEmpty else {
            let phase: SyncPhase = retainedCount == 0 ? .idle : .error
            await updateStatus(phase: phase, pendingCount: retainedCount)
            return
        }

        let total = snapshots.count
        await updateStatus(phase: .syncing, pendingCount: retainedCount)
        logger.info("SyncEngine: draining \(total) mutation(s)")

        var remaining = retainedCount
        for snapshot in snapshots {
            do {
                try Task.checkCancellation()
                try await store.markInflight(mutationId: snapshot.mutationId)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                logger.warning("SyncEngine: could not mark mutation inflight")
            }

            do {
                try Task.checkCancellation()
                let outcome = try await withAsyncRetry(
                    maxAttempts: 3,
                    initialDelay: .milliseconds(500),
                    multiplier: 2.0,
                    shouldRetry: { ($0 as? AppError)?.isRetryable ?? false }
                ) { [self] in
                    try await self.dispatchMutation(snapshot)
                }
                try Task.checkCancellation()
                let didDelete = try await resolveDispatchOutcome(outcome, for: snapshot)
                try Task.checkCancellation()
                if didDelete {
                    remaining -= 1
                    await updateStatus(phase: .syncing, pendingCount: remaining)
                    logger.info("SyncEngine: applied mutation")
                }
            } catch is CancellationError {
                return
            } catch let error as AppError {
                if error.isAuthenticationFailure {
                    // Stop the drain — user needs to re-authenticate before we retry.
                    logger.warning("SyncEngine: auth failure during drain, stopping")
                    await recordFailure(snapshot: snapshot, error: error)
                    await updateStatus(
                        phase: .error,
                        pendingCount: remaining,
                        error: MutationFailureCode.authentication.rawValue
                    )
                    break
                }
                await recordFailure(snapshot: snapshot, error: error)
            } catch {
                await recordFailure(snapshot: snapshot, error: error)
            }
        }

        await publishFinalDrainStatus(userId: userId, fallbackCount: remaining)
    }

    private func publishFinalDrainStatus(userId: String, fallbackCount: Int) async {
        guard !Task.isCancelled else { return }
        let finalCount = (try? await store.countPendingMutations(userId: userId)) ?? fallbackCount
        guard !Task.isCancelled else { return }
        let finalPhase: SyncPhase = finalCount == 0 ? .idle : .error
        await updateStatus(phase: finalPhase, pendingCount: finalCount)

        if finalCount == 0 {
            let now = Date()
            await MainActor.run { status.lastSyncedDate = now }
            logger.info("SyncEngine: drain complete — outbox empty")
        } else {
            logger.warning("SyncEngine: drain finished with \(finalCount) unsynced mutation(s)")
        }
    }

    // MARK: - Failure handling

    @discardableResult
    func resolveDispatchOutcome(
        _ outcome: MutationDispatchOutcome,
        for snapshot: SyncMutationSnapshot
    ) async throws -> Bool {
        try Task.checkCancellation()
        switch outcome {
        case .applied, .alreadyApplied:
            return try await store.deleteMutation(mutationId: snapshot.mutationId)
        case .quarantined(let reason):
            try await store.markQuarantined(
                mutationId: snapshot.mutationId,
                reason: reason
            )
            logger.warning(
                "SyncEngine: quarantined mutation: \(reason.safeCode, privacy: .public)"
            )
            return false
        }
    }

    private func recordFailure(snapshot: SyncMutationSnapshot, error: Error) async {
        guard !(error is CancellationError), !Task.isCancelled else { return }
        let failureCode = MutationFailureCode(error: error)
        logger.error(
            "SyncEngine: mutation failed: \(failureCode.rawValue, privacy: .public)"
        )
        do {
            try Task.checkCancellation()
            try await store.markFailed(
                mutationId: snapshot.mutationId,
                failureCode: failureCode
            )
        } catch is CancellationError {
            return
        } catch {
            logger.error("SyncEngine: could not record mutation failure")
        }
    }

    // MARK: - Status update

    private func updateStatus(phase: SyncPhase, pendingCount: Int, error: String? = nil) async {
        let p = phase; let c = pendingCount; let e = error
        await MainActor.run {
            status.phase = p
            status.pendingCount = c
            status.lastError = e
        }
    }
}
