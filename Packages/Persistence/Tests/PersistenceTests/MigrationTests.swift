import Foundation
import SwiftData
import Testing
@testable import Persistence

// MARK: - Schema Migration Tests

/// Tests for the SwiftData schema migration plan and corruption-recovery fallback.
///
/// Migration tests require on-disk temporary stores because in-memory stores cannot
/// persist data between two separate `ModelContainer` opens. Each test creates a
/// unique temp URL and cleans up in a `defer` block.
///
/// The `.serialized` trait prevents concurrent container creation and matches the
/// precaution taken in `OfflineSchemaTests` for the CoreData entity-description
/// re-registration issue on Darwin 25 / macOS 26.
@Suite("SchemaMigration", .serialized)
struct SchemaMigrationTests {

    // MARK: - Helpers

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "cf_mig_\(UUID().uuidString).store")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: - Plan shape

    @Test("currentVersion constant matches the latest VersionedSchema")
    func currentVersionMatchesLatest() {
        #expect(PersistenceMigrationPlan.currentVersion == PersistenceSchemaV7.versionIdentifier)
        #expect(PersistenceMigrationPlan.currentVersion == Schema.Version(7, 0, 0))
    }

    @Test("migration plan has 7 schemas and 6 lightweight stages")
    func planShape() {
        #expect(PersistenceMigrationPlan.schemas.count == 7)
        #expect(PersistenceMigrationPlan.stages.count == 6)
    }

    // MARK: - V1 → V2 lightweight migration with seeded data

    /// Seeds a V1 store (CachedKeyValue only), then reopens it with the V2 schema
    /// and the full migration plan. Verifies that every seeded record survives the
    /// lightweight migration and that the new V2 tables exist but are empty.
    @Test("seeded V1 CachedKeyValue records survive lightweight migration to V2")
    func v1ToV2MigrationSeedsData() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        // Step 1 — seed V1 data using the V1 schema only.
        do {
            let v1Schema = Schema(PersistenceSchemaV1.models)
            let v1Config = ModelConfiguration(schema: v1Schema, url: url)
            let v1Container = try ModelContainer(for: v1Schema, configurations: v1Config)
            let ctx = ModelContext(v1Container)
            ctx.insert(CachedKeyValue(key: "habit", value: "read-daily"))
            ctx.insert(CachedKeyValue(key: "streak", value: "7"))
            try ctx.save()
            // v1Container exits scope here; ARC releases it and SQLite WAL is flushed.
        }

        // Step 2 — reopen with V2 schema + migration plan.
        let v2Schema = Schema(PersistenceSchemaV2.models)
        let v2Config = ModelConfiguration(schema: v2Schema, url: url)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: PersistenceMigrationPlan.self,
            configurations: v2Config
        )
        let ctx2 = ModelContext(v2Container)

        // Step 3 — assert V1 records survived the migration.
        let fetched = try ctx2.fetch(
            FetchDescriptor<CachedKeyValue>(sortBy: [SortDescriptor(\.key)])
        )
        #expect(fetched.count == 2)
        #expect(fetched[0].key == "habit")
        #expect(fetched[0].value == "read-daily")
        #expect(fetched[1].key == "streak")
        #expect(fetched[1].value == "7")

        // V2-only tables exist but are empty (additive migration, no back-fill).
        #expect(try ctx2.fetchCount(FetchDescriptor<LocalAnnotation>()) == 0)
        #expect(try ctx2.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 0)
    }

    // MARK: - Corruption recovery: unreadable store

    /// Writes garbage bytes to a store URL, then triggers recovery.
    /// Verifies that the outcome is `recoveredCacheRebuiltOutboxLost` (no outbox to
    /// salvage from garbage) and that the fresh store is functional.
    @Test("unreadable store recovers with empty outbox (recoveredCacheRebuiltOutboxLost)")
    func corruptStoreOutboxLost() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        try Data("NOT A VALID SQLITE DATABASE FILE".utf8).write(to: url)

        let result = try StoreRecoveryManager.recoverStore(
            at: url,
            originalError: PersistenceError.notFound
        )

        #expect(result.outcome == .recoveredCacheRebuiltOutboxLost)

        // Fresh store is functional.
        let ctx = ModelContext(result.controller.container)
        ctx.insert(CachedKeyValue(key: "post-recovery", value: "ok"))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<CachedKeyValue>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<PendingMutation>()) == 0)
    }

    // MARK: - Corruption recovery: outbox preservation

    /// Creates a store containing only PendingMutation records (simulating the scenario
    /// where cache tables are corrupted but the outbox table is intact), then triggers
    /// recovery. Verifies that both mutations survive in the fresh store and that cache
    /// tables are empty (to be rebuilt from the server).
    @Test("recoverable outbox is preserved across store rebuild")
    func corruptStoreOutboxPreserved() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        // Step 1 — write a store with only PendingMutation records.
        // Opening with a subset schema models "cache tables broken, outbox intact."
        do {
            let minSchema = Schema([PendingMutation.self])
            let minConfig = ModelConfiguration(schema: minSchema, url: url)
            let minContainer = try ModelContainer(for: minSchema, configurations: minConfig)
            let ctx = ModelContext(minContainer)
            ctx.insert(PendingMutation(
                mutationId: "mut-alpha",
                userId: "user-1",
                kindRaw: MutationKind.progressCursor.rawValue,
                payloadJSON: "{\"chapterNumber\":5}"
            ))
            ctx.insert(PendingMutation(
                mutationId: "mut-beta",
                userId: "user-1",
                kindRaw: MutationKind.readingSession.rawValue,
                payloadJSON: "{\"minutes\":15}"
            ))
            try ctx.save()
        }

        // Step 2 — trigger recovery (simulates the V7 schema open having failed).
        let result = try StoreRecoveryManager.recoverStore(
            at: url,
            originalError: PersistenceError.notFound
        )

        // Outcome reflects that both mutations were salvaged.
        #expect(result.outcome == .recoveredCacheRebuilt(salvaged: 2))

        // Both mutations are present in the fresh V7 store.
        let ctx = ModelContext(result.controller.container)
        let mutations = try ctx.fetch(
            FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.mutationId)])
        )
        #expect(mutations.count == 2)
        #expect(mutations[0].mutationId == "mut-alpha")
        #expect(mutations[0].kindRaw == MutationKind.progressCursor.rawValue)
        #expect(mutations[1].mutationId == "mut-beta")
        #expect(mutations[1].kindRaw == MutationKind.readingSession.rawValue)

        // Cache tables are empty — the caller must trigger a server sync.
        #expect(try ctx.fetchCount(FetchDescriptor<CachedBook>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<CachedChapter>()) == 0)
    }

    // MARK: - Healthy open (end-to-end)

    @Test("openWithRecovery returns .healthy for a valid store")
    func healthyOpen() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        let result = try StoreRecoveryManager.openWithRecovery(storage: .privateStore(url))
        #expect(result.outcome == .healthy)

        // Smoke: store is fully functional after a healthy open.
        let ctx = ModelContext(result.controller.container)
        ctx.insert(CachedKeyValue(key: "smoke", value: "test"))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<CachedKeyValue>()) == 1)
    }

    // MARK: - Outbox payload fidelity after recovery

    /// After recovery the outbox mutations must round-trip their payloads losslessly,
    /// since the SyncEngine replays them verbatim.
    @Test("salvaged mutation payload survives recovery without modification")
    func outboxPayloadFidelity() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        struct ProgressPayload: Codable, Equatable {
            var bookId: String
            var chapterNumber: Int
        }
        let original = ProgressPayload(bookId: "book-42", chapterNumber: 7)
        let originalJSON = String(bytes: try JSONEncoder().encode(original), encoding: .utf8)!

        do {
            let minSchema = Schema([PendingMutation.self])
            let minConfig = ModelConfiguration(schema: minSchema, url: url)
            let container = try ModelContainer(for: minSchema, configurations: minConfig)
            let ctx = ModelContext(container)
            ctx.insert(PendingMutation(
                mutationId: "payload-test",
                userId: "u",
                kindRaw: MutationKind.progressCursor.rawValue,
                payloadJSON: originalJSON
            ))
            try ctx.save()
        }

        let result = try StoreRecoveryManager.recoverStore(
            at: url,
            originalError: PersistenceError.notFound
        )
        #expect(result.outcome == .recoveredCacheRebuilt(salvaged: 1))

        let ctx = ModelContext(result.controller.container)
        let mutation = try ctx.fetch(FetchDescriptor<PendingMutation>()).first
        let decoded = try mutation?.decodePayload(as: ProgressPayload.self)
        #expect(decoded == original)
    }
}
