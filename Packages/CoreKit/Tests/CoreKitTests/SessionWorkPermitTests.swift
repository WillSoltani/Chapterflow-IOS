import Foundation
import os
import Testing
@testable import CoreKit

@Suite("SessionWorkPermit")
struct SessionWorkPermitTests {
    @Test("active ticket commits synchronously")
    func activeTicketCommits() throws {
        let permit = SessionWorkPermit()
        let ticket = try permit.begin()

        let value = try permit.commit(ticket) { 42 }

        #expect(value == 42)
        #expect(permit.currentState() == .active)
        try permit.validate(ticket)
    }

    @Test("quiesce and resume reject the old generation")
    func resumeDoesNotResurrectOldTicket() throws {
        let permit = SessionWorkPermit()
        let oldTicket = try permit.begin()

        permit.quiesce()

        #expect(permit.currentState() == .quiesced)
        #expect(throws: CancellationError.self) {
            _ = try permit.begin()
        }

        permit.resume()
        let newTicket = try permit.begin()
        var staleCommitRan = false

        #expect(permit.currentState() == .active)
        #expect(newTicket != oldTicket)
        #expect(throws: CancellationError.self) {
            try permit.validate(oldTicket)
        }
        #expect(throws: CancellationError.self) {
            try permit.commit(oldTicket) {
                staleCommitRan = true
            }
        }
        #expect(staleCommitRan == false)
        try permit.validate(newTicket)
    }

    @Test("invalidation is permanent")
    func invalidationIsPermanent() throws {
        let permit = SessionWorkPermit()
        let ticket = try permit.begin()

        permit.invalidate()
        permit.resume()
        permit.quiesce()

        #expect(permit.currentState() == .invalidated)
        #expect(throws: CancellationError.self) {
            _ = try permit.begin()
        }
        #expect(throws: CancellationError.self) {
            try permit.validate(ticket)
        }
        #expect(throws: CancellationError.self) {
            try permit.commit(ticket) {}
        }
    }

    @Test("quiesce waits for an in-progress commit closure")
    func quiesceWaitsForCommit() throws {
        let permit = SessionWorkPermit()
        let ticket = try permit.begin()
        let events = EventRecorder()
        let commitEntered = DispatchSemaphore(value: 0)
        let releaseCommit = DispatchSemaphore(value: 0)
        let commitClosureExited = DispatchSemaphore(value: 0)
        let quiesceAttempting = DispatchSemaphore(value: 0)
        let quiesceReturned = DispatchSemaphore(value: 0)
        let deadline: DispatchTimeInterval = .seconds(5)
        defer { releaseCommit.signal() }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? permit.commit(ticket) {
                events.append(.commitEntered)
                commitEntered.signal()
                releaseCommit.wait()
                events.append(.commitExited)
                commitClosureExited.signal()
            }
        }

        try #require(commitEntered.wait(timeout: .now() + deadline) == .success)

        DispatchQueue.global(qos: .userInitiated).async {
            events.append(.quiesceAttempting)
            quiesceAttempting.signal()
            permit.quiesce()
            events.append(.quiesceReturned)
            quiesceReturned.signal()
        }

        try #require(quiesceAttempting.wait(timeout: .now() + deadline) == .success)
        let returnedBeforeRelease = quiesceReturned.wait(
            timeout: .now() + .milliseconds(100)
        ) == .success
        #expect(returnedBeforeRelease == false)

        releaseCommit.signal()

        try #require(commitClosureExited.wait(timeout: .now() + deadline) == .success)
        if !returnedBeforeRelease {
            try #require(quiesceReturned.wait(timeout: .now() + deadline) == .success)
        }

        #expect(permit.currentState() == .quiesced)
        #expect(events.snapshot == [
            .commitEntered,
            .quiesceAttempting,
            .commitExited,
            .quiesceReturned,
        ])
    }
}

private enum PermitEvent: Sendable, Equatable {
    case commitEntered
    case quiesceAttempting
    case commitExited
    case quiesceReturned
}

private final class EventRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [PermitEvent]())

    var snapshot: [PermitEvent] {
        storage.withLock { $0 }
    }

    func append(_ event: PermitEvent) {
        storage.withLock { $0.append(event) }
    }
}
