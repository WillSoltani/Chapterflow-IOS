import Foundation
import SwiftData
import Testing
import CoreKit
import Models
import Networking
import Persistence
@testable import SyncEngine

// MARK: - Shared infrastructure (private to this file)

private let drainContainer: ModelContainer = {
    let schema = Schema(PersistenceSchemaV7.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    return try! ModelContainer(for: schema, configurations: config)
}()

@MainActor
private func freshDrainContext() throws -> ModelContext {
    let ctx = drainContainer.mainContext
    try ctx.delete(model: PendingMutation.self)
    try ctx.save()
    return ctx
}

private final class DrainMockClient: APIClientProtocol, @unchecked Sendable {
    private(set) var callCount = 0
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        callCount += 1
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }
}

// MARK: - drainAndWait tests

@Suite("SyncEngine drainAndWait", .serialized)
struct DrainAndWaitTests {

    @Test("drainAndWait blocks until the outbox is empty")
    @MainActor
    func drainAndWaitCompletesBeforeReturning() async throws {
        let ctx = try freshDrainContext()
        // progressCursor decodes cleanly from "{}" so the dispatch succeeds
        // and the mutation is deleted from the outbox.
        ctx.insert(PendingMutation(
            mutationId: "m-wait-1",
            userId: "u-drainwait",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-1\"}"
        ))
        try ctx.save()

        let mock = DrainMockClient()
        let engine = SyncEngine(apiClient: mock, container: drainContainer)
        await engine.drainAndWait(userId: "u-drainwait")

        #expect(mock.callCount == 1)
        let remaining = try ctx.fetchCount(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == "u-drainwait" }
        ))
        #expect(remaining == 0)
    }

    @Test("drainAndWait cancels any in-flight triggerDrain before starting")
    @MainActor
    func drainAndWaitCancelsExistingDrain() async throws {
        let ctx = try freshDrainContext()
        for index in 0..<3 {
            ctx.insert(PendingMutation(
                mutationId: "m-cancel-\(index)",
                userId: "u-cancel",
                kindRaw: MutationKind.progressCursor.rawValue,
                payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-\(index + 1)\"}"
            ))
        }
        try ctx.save()

        let mock = DrainMockClient()
        let engine = SyncEngine(apiClient: mock, container: drainContainer)

        await engine.triggerDrain(userId: "u-cancel")
        await engine.drainAndWait(userId: "u-cancel")

        let remaining = try ctx.fetchCount(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == "u-cancel" }
        ))
        #expect(remaining == 0)
    }
}
