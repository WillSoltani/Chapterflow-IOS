import Foundation
import Testing
@testable import CoreKit

@Suite("Bounded API observation health recorder")
struct APIObservationHealthRecorderTests {
    @Test("capacity is fixed at 128 and oldest events are evicted deterministically")
    func boundedEviction() {
        let recorder = APIObservationHealthRecorder()

        for index in 1...129 {
            recorder.record(observation(statusCode: 200 + index))
        }

        let snapshot = recorder.snapshot()
        #expect(APIObservationHealthRecorder.capacity == 128)
        #expect(snapshot.capacity == 128)
        #expect(snapshot.events.count == 128)
        #expect(snapshot.events.first?.statusCode == 202)
        #expect(snapshot.events.last?.statusCode == 329)
    }

    @Test("sequential recording preserves completion order")
    func sequentialOrder() {
        let recorder = APIObservationHealthRecorder()

        recorder.record(observation(statusCode: 201))
        recorder.record(observation(statusCode: 202))
        recorder.record(observation(statusCode: 203))

        #expect(recorder.snapshot().events.compactMap(\.statusCode) == [201, 202, 203])
    }

    @Test("concurrent recording and snapshotting remain bounded and race-free")
    func concurrentRecordingAndSnapshotting() async {
        let recorder = APIObservationHealthRecorder()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<512 {
                group.addTask {
                    recorder.record(self.observation(statusCode: 200 + (index % 300)))
                }
                group.addTask {
                    let snapshot = recorder.snapshot()
                    #expect(snapshot.events.count <= snapshot.capacity)
                }
            }
        }

        let snapshot = recorder.snapshot()
        #expect(snapshot.events.count == APIObservationHealthRecorder.capacity)
        #expect(snapshot.events.count <= snapshot.capacity)
    }

    @Test("session transition clears events and advances a closed generation")
    func sessionTransitionClearsAndAdvances() {
        let recorder = APIObservationHealthRecorder(initialSessionState: .signedIn)
        recorder.record(observation(statusCode: 200))
        let before = recorder.snapshot()

        recorder.transition(to: .signedOut)

        let after = recorder.snapshot()
        #expect(after.events.isEmpty)
        #expect(after.sessionState == .signedOut)
        #expect(after.sessionGeneration == before.sessionGeneration + 1)
    }

    @Test("an event captured before a session transition cannot enter the later session")
    func staleCompletionIsRejected() {
        let recorder = APIObservationHealthRecorder(initialSessionState: .signedIn)
        let staleContext = recorder.captureContext()

        recorder.beginSessionTransition()
        recorder.completeSessionTransition(to: .signedIn)
        recorder.record(observation(statusCode: 200), context: staleContext)

        #expect(recorder.snapshot().events.isEmpty)

        let currentContext = recorder.captureContext()
        recorder.record(observation(statusCode: 201), context: currentContext)
        #expect(recorder.snapshot().events.map(\.statusCode) == [201])
    }

    @Test("a later signed-in session cannot retrieve prior-session events")
    func laterSessionIsolation() {
        let recorder = APIObservationHealthRecorder(initialSessionState: .signedIn)
        recorder.record(observation(statusCode: 200))

        recorder.transition(to: .signedOut)
        recorder.transition(to: .signedIn)
        recorder.record(observation(statusCode: 201))

        let snapshot = recorder.snapshot()
        #expect(snapshot.sessionState == .signedIn)
        #expect(snapshot.events.map(\.statusCode) == [201])
    }

    @Test("snapshot reflection exposes only the closed allowlisted surface")
    func snapshotReflectionIsPrivacySafe() {
        let recorder = APIObservationHealthRecorder(initialSessionState: .signedIn)
        recorder.record(APIRequestObservation(
            method: .get,
            route: "/book/books/private-book-id?token=secret-token-value",
            attempt: 1,
            elapsed: .milliseconds(5),
            outcome: .success,
            statusCode: 200,
            requestId: "private-user@example.com",
            retryDisposition: .final
        ))

        let snapshot = recorder.snapshot()
        let fieldNames = Set(Mirror(reflecting: snapshot).children.compactMap(\.label))
        #expect(fieldNames == ["capacity", "events", "sessionGeneration", "sessionState"])

        let reflection = String(reflecting: snapshot).lowercased()
        for forbidden in [
            "private-book-id",
            "secret-token-value",
            "private-user@example.com",
            "authorization",
            "bearer",
            "cognito",
            "appconfig",
            "localizeddescription",
        ] {
            #expect(!reflection.contains(forbidden))
        }
    }

    private func observation(statusCode: Int) -> APIRequestObservation {
        APIRequestObservation(
            method: .get,
            route: "/book/books",
            attempt: 1,
            elapsed: .milliseconds(5),
            outcome: .success,
            statusCode: statusCode,
            requestId: nil,
            retryDisposition: .final
        )
    }
}
