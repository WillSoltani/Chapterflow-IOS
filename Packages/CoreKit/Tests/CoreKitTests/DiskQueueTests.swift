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
        // Allow the opt-out clear Task to run.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await diskQueue.isEmpty)
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
}
