import Testing
@testable import PaywallFeature

@Suite("Async event broadcaster")
struct AsyncEventBroadcasterTests {
    @Test(
        "subscriber created after publication receives the latest invalidation",
        .timeLimit(.minutes(1))
    )
    func lateSubscriberReceivesLatestEvent() async {
        let broadcaster = AsyncEventBroadcaster<Int>()
        await broadcaster.publish(42)

        let stream = await broadcaster.stream()
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == 42)
    }
}
