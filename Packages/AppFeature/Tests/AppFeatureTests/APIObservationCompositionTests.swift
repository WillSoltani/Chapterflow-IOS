import AuthKit
import CoreKit
import Foundation
import Networking
import os
import Persistence
import Testing
@testable import AppFeature

@Suite("Live API observation composition", .serialized)
@MainActor
struct APIObservationCompositionTests {
    @Test("one decoded live-composition request reaches breadcrumb and recorder exactly once")
    func liveCompositionExactOnce() async throws {
        let reporter = BreadcrumbReporter()
        let composition = LiveAPIClientComposition(
            config: testConfig(),
            tokenProvider: PublicTokenProvider(),
            session: successfulSession(),
            reporter: reporter,
            initialSessionState: .signedOut
        )

        let response: BooksPayload = try await composition.client.send(Endpoint(
            method: .get,
            path: "/book/books",
            requiresAuth: false
        ))

        #expect(response.books == ["kept"])
        #expect(reporter.breadcrumbs.count == 1)
        #expect(composition.healthRecorder.snapshot().events.count == 1)
        #expect(composition.healthRecorder.snapshot().events.first?.outcome == .success)
    }

    @Test("no-op crash reporting cannot alter the API result or health record")
    func unavailableCrashReportingIsIsolated() async throws {
        let composition = LiveAPIClientComposition(
            config: testConfig(),
            tokenProvider: PublicTokenProvider(),
            session: successfulSession(),
            reporter: NoopCrashReporter(),
            initialSessionState: .signedOut
        )

        let response: BooksPayload = try await composition.client.send(Endpoint(
            method: .get,
            path: "/book/books",
            requiresAuth: false
        ))

        #expect(response.books == ["kept"])
        #expect(composition.healthRecorder.snapshot().events.count == 1)
    }

    @Test("AppModel clears before sign-out and isolates the next signed-in generation")
    func appModelSessionLifecycle() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let model = makeTestAppModel(session: session)
        let oldEvent = observation(statusCode: 299)
        model.apiObservationHealthRecorder.record(oldEvent)
        let before = model.apiObservationHealthSnapshot()

        await model.signOut()

        let signedOut = model.apiObservationHealthSnapshot()
        #expect(signedOut.sessionState == .signedOut)
        #expect(signedOut.sessionGeneration > before.sessionGeneration)
        #expect(!signedOut.events.contains(oldEvent))

        session.stepUpCompleted()
        await waitForObservationState(.signedIn, model: model)
        model.apiObservationHealthRecorder.record(observation(statusCode: 201))

        let laterSession = model.apiObservationHealthSnapshot()
        #expect(laterSession.sessionState == .signedIn)
        #expect(laterSession.events.map(\.statusCode) == [201])
    }

    private func testConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowTests",
            cognitoClientID: "chapterflowtestsclient12345",
            cognitoDomain: "auth.chapterflow.test"
        )
    }

    private func successfulSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SuccessfulObservationURLProtocol.self]
        return URLSession(configuration: configuration)
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

    private func waitForObservationState(
        _ expected: APIObservationSessionState,
        model: AppModel
    ) async {
        for _ in 0..<20 {
            if model.apiObservationHealthSnapshot().sessionState == expected {
                return
            }
            await Task.yield()
        }
        Issue.record("observation session state did not become \(expected)")
    }
}

private struct BooksPayload: Decodable, Sendable, Equatable {
    let books: [String]
}

private actor PublicTokenProvider: TokenProviding {
    func validToken() async throws -> String? { nil }
    func refresh() async throws {}
    func stepUp() async throws {}
    func reportSessionError(_ error: AppError) async {}
}

private final class BreadcrumbReporter: CrashReporter, Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [CrashBreadcrumb]())

    var breadcrumbs: [CrashBreadcrumb] {
        storage.withLock { $0 }
    }

    func setUser(id: String?) {}

    func addBreadcrumb(_ breadcrumb: CrashBreadcrumb) {
        storage.withLock { $0.append(breadcrumb) }
    }

    func captureError(_ error: any Error, context: [String: String]) {}
    func captureMessage(_ message: String, level: CrashBreadcrumb.Level) {}
}

private final class SuccessfulObservationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: #"{"books":["kept"]}"#.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
