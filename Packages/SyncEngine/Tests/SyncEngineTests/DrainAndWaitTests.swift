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

private actor StopResumeDrainClient: APIClientProtocol {
    struct Metrics: Sendable {
        let attemptCount: Int
        let successfulDispatchCount: Int
        let maximumConcurrentRequestCount: Int
    }

    private var attemptCount = 0
    private var successfulDispatchCount = 0
    private var activeRequestCount = 0
    private var maximumConcurrentRequestCount = 0
    private var firstRequestStarted = false
    private var firstCancellationObserved = false
    private var firstRequestGate: CheckedContinuation<Void, Never>?
    private var firstRequestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstCancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        attemptCount += 1
        let attempt = attemptCount
        activeRequestCount += 1
        maximumConcurrentRequestCount = max(maximumConcurrentRequestCount, activeRequestCount)
        defer { activeRequestCount -= 1 }

        if attempt == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    firstRequestGate = continuation
                    firstRequestStarted = true
                    let waiters = firstRequestStartWaiters
                    firstRequestStartWaiters.removeAll()
                    for waiter in waiters {
                        waiter.resume()
                    }
                }
            } onCancel: {
                Task { await self.noteFirstCancellation() }
            }
            try Task.checkCancellation()
        }

        successfulDispatchCount += 1
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }

    func waitForFirstRequestToStart() async {
        guard !firstRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstRequestStartWaiters.append(continuation)
        }
    }

    func waitForFirstCancellation() async {
        guard !firstCancellationObserved else { return }
        await withCheckedContinuation { continuation in
            firstCancellationWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        firstRequestGate?.resume()
        firstRequestGate = nil
    }

    func metrics() -> Metrics {
        Metrics(
            attemptCount: attemptCount,
            successfulDispatchCount: successfulDispatchCount,
            maximumConcurrentRequestCount: maximumConcurrentRequestCount
        )
    }

    private func noteFirstCancellation() {
        guard !firstCancellationObserved else { return }
        firstCancellationObserved = true
        let waiters = firstCancellationWaiters
        firstCancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor CompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
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

    @Test("stop joins cancellation before the same engine resumes the mutation")
    @MainActor
    func stopJoinsBeforeResumeWithoutDuplicateDispatch() async throws {
        let ctx = try freshDrainContext()
        ctx.insert(PendingMutation(
            mutationId: "m-stop-resume",
            userId: "u-stop-resume",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-1\"}"
        ))
        try ctx.save()

        let client = StopResumeDrainClient()
        let engine = SyncEngine(apiClient: client, container: drainContainer)
        await engine.triggerDrain(userId: "u-stop-resume")
        await client.waitForFirstRequestToStart()

        let completion = CompletionProbe()
        let stopTask = Task {
            await engine.stop()
            await completion.markCompleted()
        }
        await client.waitForFirstCancellation()

        // Cancellation has reached the request, but teardown must still wait
        // for that operation to unwind before a scope can resume.
        #expect(await completion.isCompleted() == false)

        await client.releaseFirstRequest()
        await stopTask.value
        #expect(await completion.isCompleted())

        let retained = try ctx.fetch(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.mutationId == "m-stop-resume" }
        ))
        let retainedMutation = try #require(retained.first)
        #expect(retainedMutation.statusRaw != MutationStatus.failed.rawValue)
        #expect(retainedMutation.attemptCount == 0)

        await engine.start(userId: "u-stop-resume")
        await engine.waitForCurrentDrain()

        let metrics = await client.metrics()
        #expect(metrics.attemptCount == 2)
        #expect(metrics.successfulDispatchCount == 1)
        #expect(metrics.maximumConcurrentRequestCount == 1)
        let remaining = try ctx.fetchCount(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == "u-stop-resume" }
        ))
        #expect(remaining == 0)

        await engine.stop()
    }
}
