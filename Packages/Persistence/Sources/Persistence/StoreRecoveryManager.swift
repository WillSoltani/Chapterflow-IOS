#if DEBUG
import Foundation
import SwiftData

// MARK: - StoreRecoveryOutcome

/// Describes what happened when the persistent store was opened.
public enum StoreRecoveryOutcome: Sendable, Equatable {
    /// The store opened normally; all data is intact.
    case healthy
    /// The store was corrupted and rebuilt from scratch.
    ///
    /// `salvaged` is the number of ``PendingMutation`` outbox entries that were
    /// preserved across the recovery. The rebuildable server-backed cache has been
    /// dropped and must be re-fetched from the server.
    case recoveredCacheRebuilt(salvaged: Int)
    /// The store was corrupted and rebuilt, but the ``PendingMutation`` outbox
    /// could not be salvaged. Any queued, unsynced writes are lost.
    case recoveredCacheRebuiltOutboxLost
}

// MARK: - StoreOpenResult

/// The result of opening the SwiftData store via ``StoreRecoveryManager``.
public struct StoreOpenResult: Sendable {
    /// The ready-to-use persistence controller.
    public let controller: PersistenceController
    /// What happened during the open attempt.
    public let outcome: StoreRecoveryOutcome
}

// MARK: - StoreRecoveryManager

/// Debug-only corruption-recovery harness retained for deterministic migration
/// tests. The live app bootstrap never invokes this destructive path.
///
/// ## Normal path
/// Tests may call ``openWithRecovery(storage:)`` to exercise a healthy open or a
/// controlled rebuild. Production uses `PersistenceController.makeDefault()` and
/// surfaces a value-free failure without deleting or resetting local data.
///
/// ## Recovery path
/// If the store fails to open (corrupted SQLite file, incompatible migration):
/// 1. Attempts to salvage ``PendingMutation`` outbox records (unsynced writes)
///    by opening the corrupted store with a minimal schema.
/// 2. Deletes the corrupted store files (the rebuildable server-backed cache).
/// 3. Creates a fresh V8 store and re-inserts any salvaged outbox records.
/// 4. Returns the fresh controller with ``StoreRecoveryOutcome/recoveredCacheRebuilt(salvaged:)``
///    or ``StoreRecoveryOutcome/recoveredCacheRebuiltOutboxLost``.
///
/// The caller should trigger a full server-sync after any non-healthy outcome to
/// repopulate the cache tables.
///
/// ## Safety invariants
/// - **Cache is rebuildable**: server-authoritative data (books, chapters, progress)
///   is re-fetched from the server after recovery; dropping it is safe.
/// - **Outbox is precious**: ``PendingMutation`` records hold unsynced writes not yet
///   acknowledged by the server. The manager salvages them before nuking the store.
/// - **Fail-safe**: if the outbox itself is unrecoverable, the manager creates an
///   empty outbox rather than risking duplicate mutations for already-synced writes.
public enum StoreRecoveryManager {
    // MARK: - Public API

    /// Opens the store at `storage` with the full V8 schema and migration plan.
    ///
    /// Falls back to corruption recovery if the store cannot be opened.
    ///
    /// - Parameter storage: Where the store lives. Defaults to the App Group container.
    /// - Returns: A ``StoreOpenResult`` containing the controller and outcome.
    /// - Throws: ``PersistenceError/appGroupUnavailable`` when the App Group container
    ///   cannot be resolved, or the underlying error for `.inMemory` storage (in-memory
    ///   stores are ephemeral and cannot be corrupted or recovered).
    public static func openWithRecovery(
        storage: StorageMode = .appGroup
    ) throws -> StoreOpenResult {
        do {
            let controller = try PersistenceController(
                models: PersistenceSchemaV8.models,
                storage: storage,
                migrationPlan: PersistenceMigrationPlan.self
            )
            return StoreOpenResult(controller: controller, outcome: .healthy)
        } catch {
            switch storage {
            case .inMemory:
                // In-memory stores are ephemeral; there is nothing to recover.
                throw error
            case .appGroup:
                guard let dir = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: AppGroup.identifier
                ) else {
                    throw PersistenceError.appGroupUnavailable
                }
                let url = dir.appending(path: "ChapterFlow.store")
                return try recoverStore(at: url)
            case .privateStore(let url):
                return try recoverStore(at: url)
            }
        }
    }

    // MARK: - Internal (testable)

    /// Performs corruption recovery for the store file at `url`.
    ///
    /// Exposed as `internal` (not `private`) so unit tests can call it directly
    /// without requiring App Group container access.
    static func recoverStore(at url: URL) throws -> StoreOpenResult {
        // Step 1: Salvage the PendingMutation outbox before deleting the store.
        // The outbox holds queued writes that are not yet server-acknowledged.
        let salvaged = salvageOutbox(at: url)

        // Step 2: Delete the corrupted store files.
        // Cache models (books, chapters, progress, etc.) are server-authoritative and
        // rebuildable via a sync after recovery — dropping them here is safe.
        deleteStoreFiles(at: url)

        // Step 3: Create a fresh V7 store (no migration plan — writing from scratch).
        let controller = try PersistenceController(
            models: PersistenceSchemaV8.models,
            storage: .privateStore(url)
        )

        // Step 4: Re-insert salvaged outbox mutations into the fresh store.
        if !salvaged.isEmpty {
            let context = ModelContext(controller.container)
            for mutation in salvaged {
                context.insert(mutation.toPendingMutation())
            }
            try context.save()
        }

        let outcome: StoreRecoveryOutcome = salvaged.isEmpty
            ? .recoveredCacheRebuiltOutboxLost
            : .recoveredCacheRebuilt(salvaged: salvaged.count)

        return StoreOpenResult(controller: controller, outcome: outcome)
    }

    // MARK: - Private helpers

    /// A lightweight, `Sendable` value type carrying ``PendingMutation`` fields
    /// across model-container boundaries during recovery.
    struct SalvagedMutation: Sendable {
        let mutationId: String
        let userId: String
        let kindRaw: String
        let payloadJSON: String
        let createdAt: Date
        let attemptCount: Int
        let lastError: String?
        let statusRaw: String

        func toPendingMutation() -> PendingMutation {
            PendingMutation(
                mutationId: mutationId,
                userId: userId,
                kindRaw: kindRaw,
                payloadJSON: payloadJSON,
                createdAt: createdAt,
                attemptCount: attemptCount,
                lastError: lastError,
                statusRaw: statusRaw
            )
        }
    }

    /// Opens the (possibly corrupted) store with a minimal schema containing only
    /// ``PendingMutation`` and extracts all queued mutations.
    ///
    /// If the SQLite file itself is unreadable, or the `PendingMutation` table is
    /// corrupted, returns an empty array. The recovery path continues safely with
    /// an empty outbox — no data is fabricated.
    private static func salvageOutbox(at url: URL) -> [SalvagedMutation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            // Open with just PendingMutation — no migration plan, no version check.
            // If only the cache tables are corrupted this succeeds; if the SQLite
            // file itself is unreadable this throws and we return empty.
            let schema = Schema([PendingMutation.self])
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            return mutations.map { m in
                SalvagedMutation(
                    mutationId: m.mutationId,
                    userId: m.userId,
                    kindRaw: m.kindRaw,
                    payloadJSON: m.payloadJSON,
                    createdAt: m.createdAt,
                    attemptCount: m.attemptCount,
                    lastError: m.lastError,
                    statusRaw: m.statusRaw
                )
            }
        } catch {
            return []
        }
    }

    private static func deleteStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                // The subsequent open remains authoritative and will throw if a
                // sidecar could not be removed. No raw path or error is logged.
            }
        }
    }
}
#endif
