import Foundation
import Network
import SwiftData
import CoreKit
import Networking
import Persistence
import os

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
///   its submit returns. On "server already advanced", accept server truth and
///   delete the mutation without re-submitting.
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

    /// In-memory guard preventing double-submission of the same quiz session
    /// within a single drain pass.
    var activeQuizSessionIds: Set<String> = []

    /// The current drain task, if any.
    private var drainTask: Task<Void, Never>?

    /// The network-monitor task that fires ``triggerDrain(userId:)`` on path changes.
    private var monitorTask: Task<Void, Never>?

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
    public func start(userId: String) {
        startNetworkMonitor(userId: userId)
        // Trigger an eager drain in case mutations accumulated while offline.
        triggerDrain(userId: userId)
    }

    /// Stops the sync engine (call on sign-out or app termination).
    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        drainTask?.cancel()
        drainTask = nil
        activeQuizSessionIds.removeAll()
    }

    // MARK: - Drain trigger

    /// Schedules a drain pass if one is not already running.
    ///
    /// Idempotent: calling while a drain is in progress is a no-op.
    /// The engine serialises drain passes — a new pass starts only after the
    /// previous one completes (or is cancelled).
    public func triggerDrain(userId: String) {
        guard drainTask == nil || drainTask?.isCancelled == true else { return }
        drainTask = Task { [weak self] in
            await self?.drain(userId: userId)
            await self?.clearDrainTask()
        }
    }

    private func clearDrainTask() {
        drainTask = nil
        // Reset the quiz idempotency set so the next drain pass starts fresh.
        activeQuizSessionIds.removeAll()
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor(userId: String) {
        monitorTask?.cancel()
        let monitor = NWPathMonitor()
        monitorTask = Task { [weak self] in
            for await path in Self.networkPathStream(monitor: monitor) where path.status == .satisfied {
                await self?.triggerDrain(userId: userId)
            }
        }
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
            snapshots = try await store.fetchPendingMutations(userId: userId)
        } catch {
            logger.error("SyncEngine: failed to fetch pending mutations: \(error)")
            await updateStatus(phase: .error, pendingCount: 0, error: error.localizedDescription)
            return
        }

        guard !snapshots.isEmpty else {
            await updateStatus(phase: .idle, pendingCount: 0)
            return
        }

        let total = snapshots.count
        await updateStatus(phase: .syncing, pendingCount: total)
        logger.info("SyncEngine: draining \(total) mutation(s)")

        var remaining = total
        for snapshot in snapshots {
            if Task.isCancelled { break }

            do {
                try await store.markInflight(mutationId: snapshot.mutationId)
            } catch {
                logger.warning("SyncEngine: could not mark inflight \(snapshot.mutationId): \(error)")
            }

            do {
                try await withAsyncRetry(
                    maxAttempts: 3,
                    initialDelay: .milliseconds(500),
                    multiplier: 2.0,
                    shouldRetry: { ($0 as? AppError)?.isRetryable ?? false }
                ) { [self] in
                    try await self.dispatchMutation(snapshot)
                }
                try await store.deleteMutation(mutationId: snapshot.mutationId)
                remaining -= 1
                await updateStatus(phase: .syncing, pendingCount: remaining)
                logger.info("SyncEngine: synced \(snapshot.kindRaw) (\(snapshot.mutationId))")
            } catch let error as AppError {
                if error.isAuthenticationFailure {
                    // Stop the drain — user needs to re-authenticate before we retry.
                    logger.warning("SyncEngine: auth failure during drain, stopping")
                    await updateStatus(phase: .error, pendingCount: remaining, error: error.localizedDescription)
                    break
                }
                await recordFailure(snapshot: snapshot, error: error)
            } catch {
                await recordFailure(snapshot: snapshot, error: error)
            }
        }

        let finalCount = (try? await store.countPendingMutations(userId: userId)) ?? remaining
        let finalPhase: SyncPhase = finalCount == 0 ? .idle : .error
        await updateStatus(phase: finalPhase, pendingCount: finalCount)

        if finalCount == 0 {
            logger.info("SyncEngine: drain complete — outbox empty")
        } else {
            logger.warning("SyncEngine: drain finished with \(finalCount) unsynced mutation(s)")
        }
    }

    // MARK: - Failure handling

    private func recordFailure(snapshot: SyncMutationSnapshot, error: Error) async {
        logger.error("SyncEngine: failed to sync \(snapshot.kindRaw) (\(snapshot.mutationId)): \(error)")
        do {
            try await store.markFailed(
                mutationId: snapshot.mutationId,
                errorDescription: error.localizedDescription
            )
        } catch {
            logger.error("SyncEngine: could not record failure for \(snapshot.mutationId): \(error)")
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
