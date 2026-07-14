import Foundation
import os
import Testing
@testable import CoreKit

@Suite("Composite API client observer")
struct CompositeAPIClientObserverTests {
    @Test("one event reaches every child exactly once")
    func exactOnceFanOut() {
        let first = EventObserver()
        let second = EventObserver()
        let composite = CompositeAPIClientObserver([first, second])
        let event = observation()

        composite.record(event)

        #expect(first.events == [event])
        #expect(second.events == [event])
    }

    @Test("fan-out preserves declared child order")
    func declaredOrder() {
        let order = OSAllocatedUnfairLock(initialState: [Int]())
        let composite = CompositeAPIClientObserver([
            OrderedObserver(value: 1, order: order),
            OrderedObserver(value: 2, order: order),
            OrderedObserver(value: 3, order: order),
        ])

        composite.record(observation())

        #expect(order.withLock { $0 } == [1, 2, 3])
    }

    @Test("a child that traps its own failure cannot stop a later child")
    func childFailureIsolation() {
        let rejecting = SelfRejectingObserver()
        let healthy = EventObserver()
        let composite = CompositeAPIClientObserver([rejecting, healthy])
        let event = observation()

        composite.record(event)

        #expect(rejecting.rejectionCount == 1)
        #expect(healthy.events == [event])
    }

    @Test("an unavailable crash reporter cannot prevent the health record")
    func unavailableCrashReporter() {
        let recorder = APIObservationHealthRecorder()
        let composite = CompositeAPIClientObserver([
            CrashBreadcrumbAPIObserver(reporter: NoopCrashReporter()),
            recorder,
        ])

        composite.record(observation())

        #expect(recorder.snapshot().events.count == 1)
    }

    private func observation() -> APIRequestObservation {
        APIRequestObservation(
            method: .get,
            route: "/book/books",
            attempt: 1,
            elapsed: .milliseconds(5),
            outcome: .success,
            statusCode: 200,
            requestId: nil,
            retryDisposition: .final
        )
    }
}

private final class EventObserver: APIClientObserver, Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [APIRequestObservation]())

    var events: [APIRequestObservation] {
        storage.withLock { $0 }
    }

    func record(_ event: APIRequestObservation) {
        storage.withLock { $0.append(event) }
    }
}

private final class OrderedObserver: APIClientObserver, Sendable {
    private let value: Int
    private let order: OSAllocatedUnfairLock<[Int]>

    init(value: Int, order: OSAllocatedUnfairLock<[Int]>) {
        self.value = value
        self.order = order
    }

    func record(_ event: APIRequestObservation) {
        order.withLock { $0.append(value) }
    }
}

private final class SelfRejectingObserver: APIClientObserver, Sendable {
    private enum ExpectedFailure: Error {
        case rejected
    }

    private let storage = OSAllocatedUnfairLock(initialState: 0)

    var rejectionCount: Int {
        storage.withLock { $0 }
    }

    func record(_ event: APIRequestObservation) {
        do {
            throw ExpectedFailure.rejected
        } catch {
            storage.withLock { $0 += 1 }
        }
    }
}
