import CoreKit
import Foundation
import os
import Testing
@testable import Networking

extension NetworkingTests {
    @Test("request-start context rejects an old-session completion without changing the result")
    func observationRejectsOldSessionCompletion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in
            .init(statusCode: 200, body: #"{"books":["kept"]}"#.data(using: .utf8)!)
        }
        let recorder = APIObservationHealthRecorder(initialSessionState: .signedIn)
        let observer = RotateBeforeScopedRecordObserver(recorder: recorder)
        let (client, _) = TestFactory.clientWithObserver(observer: observer)

        let response: BooksResponse = try await client.send(Endpoints.getBooks())

        #expect(response.books == ["kept"])
        #expect(recorder.snapshot().sessionState == .signedOut)
        #expect(recorder.snapshot().events.isEmpty)
    }
}

private final class RotateBeforeScopedRecordObserver: APIClientObserver, Sendable {
    private let recorder: APIObservationHealthRecorder
    private let didRotate = OSAllocatedUnfairLock(initialState: false)

    init(recorder: APIObservationHealthRecorder) {
        self.recorder = recorder
    }

    func captureContext() -> APIObservationContext {
        recorder.captureContext()
    }

    func record(_ event: APIRequestObservation) {
        recorder.record(event)
    }

    func record(_ event: APIRequestObservation, context: APIObservationContext) {
        didRotate.withLock { didRotate in
            if !didRotate {
                recorder.transition(to: .signedOut)
                didRotate = true
            }
        }
        recorder.record(event, context: context)
    }
}
