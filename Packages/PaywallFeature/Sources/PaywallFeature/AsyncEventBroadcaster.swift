import Foundation

/// Actor-isolated fan-out for events consumed through `AsyncStream`.
///
/// Every call to ``stream()`` creates an independent subscription. Publishing
/// an event yields it to every active subscriber, avoiding the work-sharing
/// behavior that results when multiple observers iterate one `AsyncStream`.
/// The latest event is replayed to a subscriber created after publication so
/// entitlement invalidations cannot be lost during listener startup.
actor AsyncEventBroadcaster<Event: Sendable> {
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var latestEvent: ReplayState<Event> = .empty
    private var publicationCount: UInt64 = 0

    func stream() -> AsyncStream<Event> {
        let subscriptionID = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream(
            // Entitlement events are invalidations: one pending refresh is
            // sufficient while a subscriber is already doing async work.
            bufferingPolicy: .bufferingNewest(1)
        )
        continuations[subscriptionID] = continuation
        if case .published(let event) = latestEvent {
            continuation.yield(event)
        }
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSubscription(subscriptionID)
            }
        }
        return stream
    }

    func publish(_ event: Event) {
        publicationCount &+= 1
        latestEvent = .published(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func publishedEventCount() -> UInt64 {
        publicationCount
    }

    private func removeSubscription(_ subscriptionID: UUID) {
        continuations.removeValue(forKey: subscriptionID)
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }
}

private enum ReplayState<Event: Sendable>: Sendable {
    case empty
    case published(Event)
}
