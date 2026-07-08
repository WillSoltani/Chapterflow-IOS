import Foundation
import SwiftData
import Testing
import CoreKit
import Models
import Networking
import Persistence
@testable import SyncEngine

// MARK: - SyncStatus tests (P3.5)

@Suite("SyncStatus — lastSyncedDate", .serialized)
struct SyncStatusLastSyncedDateTests {

    @Test("lastSyncedDate is nil before any drain runs")
    @MainActor
    func lastSyncedDateNilByDefault() {
        let mock = MockAPIClient()
        let container = makeInMemoryContainer()
        let engine = SyncEngine(apiClient: mock, container: container)
        #expect(engine.status.lastSyncedDate == nil)
    }

    @Test("lastSyncedDate is set after a successful drain that empties the outbox")
    @MainActor
    func lastSyncedDateSetAfterSuccessfulDrain() async throws {
        let container = makeInMemoryContainer()
        let ctx = container.mainContext
        // progressCursor: BookStateResponseEnvelope has all-optional fields, so "{}" decodes cleanly.
        ctx.insert(PendingMutation(
            mutationId: "m-synced",
            userId: "u-synced",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-1\"}"
        ))
        try ctx.save()

        let mock = MockAPIClient()
        let engine = SyncEngine(apiClient: mock, container: container)
        await engine.triggerDrain(userId: "u-synced")
        try await Task.sleep(for: .milliseconds(400))

        #expect(engine.status.lastSyncedDate != nil)
    }

    @Test("lastSyncedDate stays nil when drain ends with failures")
    @MainActor
    func lastSyncedDateNotSetWhenDrainFails() async throws {
        let container = makeInMemoryContainer()
        let ctx = container.mainContext
        ctx.insert(PendingMutation(
            mutationId: "m-fail",
            userId: "u-fail",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-1\"}"
        ))
        try ctx.save()

        let mock = MockAPIClient()
        mock.stubbedError = AppError.invalidInput("server rejected")
        let engine = SyncEngine(apiClient: mock, container: container)
        await engine.triggerDrain(userId: "u-fail")
        try await Task.sleep(for: .milliseconds(400))

        // Drain finished with failures — lastSyncedDate should stay nil.
        #expect(engine.status.lastSyncedDate == nil)
    }
}

// MARK: - Helpers

private func makeInMemoryContainer() -> ModelContainer {
    let schema = Schema(PersistenceSchemaV7.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    return try! ModelContainer(for: schema, configurations: config)
}

/// Minimal API client mock for SyncStatus tests.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedError: Error?

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        if let error = stubbedError { throw error }
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }
}
