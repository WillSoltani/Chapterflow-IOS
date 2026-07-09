import Testing
import Foundation
@testable import CoreKit

/// Records every payload the client hands off, and can be told to fail.
actor SpyTransport: AnalyticsTransport {
    private(set) var sent: [(path: String, payload: Data)] = []
    var failure: Error?

    init(failure: Error? = nil) { self.failure = failure }

    func send(path: String, payload: Data) async throws {
        if let failure { throw failure }
        sent.append((path, payload))
    }

    var count: Int { sent.count }
    var isEmpty: Bool { sent.isEmpty }

    /// Decodes the events array from the most recent `track` batch.
    func lastBatchEventCount() -> Int? {
        guard let data = sent.last?.payload,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["events"] as? [Any]
        else { return nil }
        return events.count
    }
}

@Suite("AnalyticsClient")
struct AnalyticsClientTests {
    private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }

    @Test("events are buffered and flushed once the batch is full")
    func batching() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 3, now: fixedNow)

        await client.record(.appOpen)
        await client.record(.signIn(method: "cognito"))
        #expect(await spy.isEmpty)          // not full yet
        #expect(await client.bufferedCount == 2)

        await client.record(.bookStarted(bookId: "b1"))  // hits batchSize → flush
        #expect(await spy.count == 1)
        #expect(await client.bufferedCount == 0)
        #expect(await spy.lastBatchEventCount() == 3)
        #expect(await spy.sent.last?.path == DefaultAnalyticsClient.Path.track)
    }

    @Test("explicit flush delivers a partial batch, and is a no-op when empty")
    func explicitFlush() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 100, now: fixedNow)

        await client.flush()                   // nothing buffered → no send
        #expect(await spy.isEmpty)

        await client.record(.paywallViewed(source: "home"))
        await client.record(.purchase(productId: "annual"))
        await client.flush()
        #expect(await spy.count == 1)
        #expect(await spy.lastBatchEventCount() == 2)
    }

    @Test("a failing transport never throws and drops the batch")
    func nonThrowingOnFailure() async {
        let spy = SpyTransport(failure: AppError.offline)
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 1, now: fixedNow)

        // record() auto-flushes at batchSize 1; must not throw despite failure.
        await client.record(.appOpen)
        await client.flush()
        await client.deliverBeacon(name: "app_will_terminate", properties: [:])

        #expect(await spy.isEmpty)          // failing transport recorded nothing
        #expect(await client.bufferedCount == 0) // batch was dropped, not requeued
    }

    @Test("beacons post immediately to the beacon path")
    func beaconDelivery() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, now: fixedNow)

        await client.deliverBeacon(name: "app_will_terminate", properties: ["reason": "background"])
        #expect(await spy.count == 1)
        #expect(await spy.sent.last?.path == DefaultAnalyticsClient.Path.beacon)
    }

    @Test("opting out discards buffered events and drops new ones")
    func optOut() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 100, now: fixedNow)

        await client.record(.appOpen)
        await client.setOptedOut(true)
        #expect(await client.bufferedCount == 0)   // buffer cleared on opt-out

        await client.record(.signIn(method: "cognito"))
        await client.deliverBeacon(name: "x", properties: [:])
        await client.flush()
        #expect(await spy.isEmpty)              // nothing sent while opted out
    }

    @Test("the fire-and-forget track API eventually delivers")
    func fireAndForgetTrack() async throws {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 1, now: fixedNow)

        client.track(.appOpen)   // sync, non-throwing

        // Poll briefly for the detached task to enqueue + flush.
        var delivered = false
        for _ in 0..<50 where !delivered {
            if await spy.count == 1 { delivered = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(delivered)
    }

    @Test("NoopAnalyticsClient does nothing and never throws")
    func noop() async {
        let client = NoopAnalyticsClient()
        client.track(.appOpen)
        client.beacon("x")
        await client.flush()
    }
}

// MARK: - AnalyticsEvent tests

@Suite("AnalyticsEvent")
struct AnalyticsEventTests {

    @Test("reviewCompleted has correct name and reviewed property")
    func reviewCompletedEvent() {
        let event = AnalyticsEvent.reviewCompleted(reviewed: 7)
        #expect(event.name == "review_completed")
        #expect(event.properties["reviewed"] == "7")
        #expect(event.properties.count == 1)
    }

    @Test("share has correct name and cardType property")
    func shareEvent() {
        let event = AnalyticsEvent.share(cardType: "streak")
        #expect(event.name == "share")
        #expect(event.properties["cardType"] == "streak")
        #expect(event.properties.count == 1)
    }

    @Test("reviewCompleted encodes through the client")
    func reviewCompletedEncodes() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 1,
                                            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await client.record(.reviewCompleted(reviewed: 3))
        #expect(await spy.count == 1)
        let data = await spy.sent.last?.payload
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        let events = json?["events"] as? [[String: Any]]
        #expect(events?.first?["name"] as? String == "review_completed")
    }

    @Test("share encodes through the client")
    func shareEncodes() async {
        let spy = SpyTransport()
        let client = DefaultAnalyticsClient(transport: spy, batchSize: 1,
                                            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await client.record(.share(cardType: "badge"))
        #expect(await spy.count == 1)
        let data = await spy.sent.last?.payload
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        let events = json?["events"] as? [[String: Any]]
        #expect(events?.first?["name"] as? String == "share")
    }
}
