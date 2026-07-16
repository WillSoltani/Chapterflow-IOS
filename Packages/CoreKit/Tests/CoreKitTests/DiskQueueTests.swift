import Testing
import Foundation
@testable import CoreKit

@Suite("DiskQueue")
struct DiskQueueTests {

    // MARK: - Helpers

    private func makeQueue(maxSize: Int = 500) -> (DiskQueue, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskQueueTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("queue.json")
        return (DiskQueue(fileURL: url, maxSize: maxSize), url)
    }

    private func makeEvent(name: String = "test_event") -> AnalyticsWireEvent {
        AnalyticsWireEvent(name: name, properties: [:], timestamp: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Tests

    @Test("empty queue returns zero count")
    func emptyQueueCount() async {
        let (queue, _) = makeQueue()
        #expect(await queue.isEmpty)
    }

    @Test("enqueued events persist across queue instances (simulates relaunch)")
    func persistenceAcrossInstances() async throws {
        let (queue1, url) = makeQueue()

        let events = [makeEvent(name: "e1"), makeEvent(name: "e2")]
        try await queue1.enqueue(events)

        // Simulate relaunch: create a fresh DiskQueue pointing at the same file.
        let queue2 = DiskQueue(fileURL: url)
        let loaded = await queue2.dequeueAll()

        #expect(loaded.count == 2)
        #expect(loaded.map(\.name) == ["e1", "e2"])
    }

    @Test("dequeueAll clears the file")
    func dequeueAllClears() async throws {
        let (queue, _) = makeQueue()
        try await queue.enqueue([makeEvent()])
        _ = await queue.dequeueAll()
        #expect(await queue.isEmpty)
    }

    @Test("dequeueAll on empty queue returns empty array")
    func dequeueEmpty() async {
        let (queue, _) = makeQueue()
        let result = await queue.dequeueAll()
        #expect(result.isEmpty)
    }

    @Test("oldest events are dropped when maxSize is exceeded")
    func dropOldest() async throws {
        let (queue, _) = makeQueue(maxSize: 3)

        let events = (1...5).map { makeEvent(name: "e\($0)") }
        try await queue.enqueue(events)

        let loaded = await queue.dequeueAll()
        #expect(loaded.count == 3)
        // Oldest (e1, e2) are dropped; newest (e3, e4, e5) survive.
        #expect(loaded.map(\.name) == ["e3", "e4", "e5"])
    }

    @Test("enqueue returns the current count")
    func enqueueReturnsCount() async throws {
        let (queue, _) = makeQueue()
        let count = try await queue.enqueue([makeEvent(), makeEvent()])
        #expect(count == 2)
    }

    @Test("clear removes all events")
    func clearRemovesAll() async throws {
        let (queue, _) = makeQueue()
        try await queue.enqueue([makeEvent(), makeEvent(), makeEvent()])
        try await queue.clear()
        #expect(await queue.isEmpty)
    }

    @Test("multiple enqueue calls accumulate events")
    func multipleEnqueueAccumulates() async throws {
        let (queue, _) = makeQueue()
        try await queue.enqueue([makeEvent(name: "a")])
        try await queue.enqueue([makeEvent(name: "b")])
        let all = await queue.dequeueAll()
        #expect(all.count == 2)
        #expect(all.map(\.name) == ["a", "b"])
    }

    @Test("events survive encode/decode round trip including Date")
    func codableRoundTrip() async throws {
        let (queue, _) = makeQueue()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let event = AnalyticsWireEvent(
            name: "chapter_opened",
            properties: ["bookId": "b1", "chapter": "3"],
            timestamp: fixedDate
        )
        try await queue.enqueue([event])
        let loaded = await queue.dequeueAll()

        let got = try #require(loaded.first)
        #expect(got.name == event.name)
        #expect(got.properties == event.properties)
        // ISO-8601 round-trip loses sub-second precision; compare within 1s.
        #expect(abs(got.timestamp.timeIntervalSince(fixedDate)) < 1)
    }
}

@Suite("DefaultAnalyticsClient (disk-backed)")
struct DiskBackedAnalyticsClientTests {
    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    private let accountA = "account-v1-" + String(repeating: "a", count: 64)
    private let accountB = "account-v1-" + String(repeating: "b", count: 64)

    private func makeDiskQueue() -> (DiskQueue, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsDiskTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("queue.json")
        return (DiskQueue(fileURL: url), url)
    }

    @Test("events survive a simulated kill+relaunch then flush")
    func surviveKillAndRelaunch() async throws {
        let (diskQueue, fileURL) = makeDiskQueue()
        let spy = SpyTransport()

        // Session 1: record two events but do NOT flush.
        let client1 = DefaultAnalyticsClient(
            transport: spy,
            batchSize: 100,
            now: fixedNow,
            diskQueue: diskQueue
        )
        await client1.record(.appOpen)
        await client1.record(.signIn(method: "cognito"))
        // Events are on disk, NOT sent yet.
        #expect(await spy.isEmpty)
        #expect(await diskQueue.count == 2)

        // Session 2: new client instance pointing at the same disk queue.
        let diskQueue2 = DiskQueue(fileURL: fileURL)
        let client2 = DefaultAnalyticsClient(
            transport: spy,
            batchSize: 100,
            now: fixedNow,
            diskQueue: diskQueue2
        )
        // Flush on "launch" drains events from disk.
        await client2.flush()
        #expect(await spy.count == 1)
        #expect(await spy.lastBatchEventCount() == 2)
    }

    @Test("opt-out clears disk queue")
    func optOutClearsDisk() async throws {
        let (diskQueue, _) = makeDiskQueue()
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(
            transport: spy,
            batchSize: 100,
            now: fixedNow,
            diskQueue: diskQueue
        )

        await client.record(.appOpen)
        #expect(await diskQueue.count == 1)

        await client.setOptedOut(true)
        #expect(await diskQueue.isEmpty)
    }

    @Test("session suspension retains A queue and only a new A client can flush it")
    func sessionSuspensionRetainsDurableQueue() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsSessionBoundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let oldTransport = SpyTransport()
        let oldClient = try DefaultAnalyticsClient.makeDurable(
            transport: oldTransport,
            batchSize: 100,
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )

        await oldClient.record(.appOpen)
        await oldClient.suspendForSessionBoundary()
        await oldClient.flush()

        #expect(await oldClient.diskQueueCount() == 1)
        #expect(await oldTransport.isEmpty)

        let resumedTransport = SpyTransport()
        let resumedClient = try DefaultAnalyticsClient.makeDurable(
            transport: resumedTransport,
            batchSize: 100,
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )
        await resumedClient.flush()

        #expect(await resumedClient.diskQueueCount() == 0)
        #expect(await resumedTransport.lastBatchEventCount() == 1)
    }

    @Test("events are re-queued to disk on send failure")
    func requeuesOnSendFailure() async throws {
        let (diskQueue, _) = makeDiskQueue()
        let spy = SpyTransport(failure: AppError.offline)
        let client = DefaultAnalyticsClient(
            transport: spy,
            batchSize: 100,
            now: fixedNow,
            diskQueue: diskQueue
        )

        await client.record(.appOpen)
        await client.flush()   // send fails → events re-queued
        // Nothing was delivered…
        #expect(await spy.isEmpty)
        // …but events remain on disk for the next attempt.
        #expect(await diskQueue.count >= 1)
    }

    @Test("blocked full-queue flush preserves a newly enqueued rollover tail")
    func blockedFlushPreservesRolloverTail() async throws {
        let (_, fileURL) = makeDiskQueue()
        let diskQueue = DiskQueue(fileURL: fileURL, maxSize: 2)
        let transport = BlockingDiskAnalyticsTransport()
        let client = DefaultAnalyticsClient(
            transport: transport,
            batchSize: 100,
            now: fixedNow,
            diskQueue: diskQueue
        )

        await client.record(.appOpen)
        await client.record(.signIn(method: "first"))
        let firstFlush = Task { await client.flush() }
        await transport.waitUntilFirstSendStarts()

        // Enqueue at max size while the original [1, 2] snapshot is in flight.
        // The queue is now [2, 3]; successful removal must retain event 3.
        await client.record(.bookStarted(bookId: "tail"))
        let overlappingFlush = Task { await client.flush() }
        while !(await client.hasPendingFlushForTest) {
            await Task.yield()
        }

        await transport.releaseFirstSend()
        await firstFlush.value
        await overlappingFlush.value

        #expect(await transport.batchSizes == [2, 1])
        #expect(await diskQueue.isEmpty)
    }

    @Test("durable queues are isolated by opaque account namespace")
    func accountQueuesAreIsolated() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsAccountIsolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let transportA = SpyTransport()
        let transportB = SpyTransport()
        let clientA = try DefaultAnalyticsClient.makeDurable(
            transport: transportA,
            batchSize: 100,
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )
        let clientB = try DefaultAnalyticsClient.makeDurable(
            transport: transportB,
            batchSize: 100,
            storageNamespace: accountB,
            applicationSupportDirectory: applicationSupport
        )

        await clientA.record(.appOpen)

        #expect(await clientA.diskQueueCount() == 1)
        #expect(await clientB.diskQueueCount() == 0)
        await clientB.flush()
        #expect(await transportB.isEmpty)

        let relaunchedA = try DefaultAnalyticsClient.makeDurable(
            transport: transportA,
            batchSize: 100,
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )
        #expect(await relaunchedA.diskQueueCount() == 1)
        await relaunchedA.flush()
        #expect(await transportA.lastBatchEventCount() == 1)
    }

    @Test("legacy unowned queue is preserved and never attributed to an account")
    func legacyQueueIsPreserved() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsLegacyPreservation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport
            .appendingPathComponent("com.chapterflow", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appendingPathComponent("analytics_queue.json")
        let legacyData = Data("legacy-unowned-queue".utf8)
        try legacyData.write(to: legacyURL)

        let client = try DefaultAnalyticsClient.makeDurable(
            transport: SpyTransport(),
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )

        #expect(await client.diskQueueCount() == 0)
        #expect(try Data(contentsOf: legacyURL) == legacyData)
    }

    @Test("invalid namespaces fail with a value-free error and create no path")
    func invalidNamespaceFailsClosedAndRedacted() {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsInvalidNamespace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let rawValue = "../private-account@example.test"

        #expect(throws: AnalyticsDurableStorageFailure.invalidStorageNamespace) {
            _ = try DefaultAnalyticsClient.makeDurable(
                transport: SpyTransport(),
                storageNamespace: rawValue,
                applicationSupportDirectory: applicationSupport
            )
        }
        #expect(!FileManager.default.fileExists(atPath: applicationSupport.path))
        let error = AnalyticsDurableStorageFailure.invalidStorageNamespace
        #expect(!String(describing: error).contains(rawValue))
        #expect(Mirror(reflecting: error).children.isEmpty)
    }
}

private actor BlockingDiskAnalyticsTransport: AnalyticsTransport {
    private(set) var batchSizes: [Int] = []
    private var firstSendStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func send(path: String, payload: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        batchSizes.append((object?["events"] as? [Any])?.count ?? 0)
        guard batchSizes.count == 1 else { return }

        firstSendStarted = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilFirstSendStarts() async {
        if firstSendStarted { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstSend() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
