import CoreKit
import SwiftUI
import Testing
@testable import AppFeature

@MainActor
@Suite("Configured app bootstrap")
struct ConfiguredAppRootViewTests {
    @Test("invalid configuration never invokes the live graph factory")
    func invalidConfigurationDoesNotBuildGraph() {
        let counter = InvocationCounter()
        let bootstrap = AppGraphBootstrap(
            config: invalidConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }

        #expect(counter.count == .zero)
        guard case .configurationFailure(let record) = bootstrap.route else {
            Issue.record("Invalid configuration reached the live application route")
            return
        }
        #expect(record.status == .invalid)
        #expect(!record.liveServicesConstructed)
        #expect(!record.issues.isEmpty)
    }

    @Test("valid configuration invokes the live graph factory exactly once")
    func validConfigurationBuildsOneGraph() {
        let counter = InvocationCounter()
        let graph = TestGraph()
        let bootstrap = AppGraphBootstrap(
            config: validConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return graph
        }

        #expect(counter.count == 1)
        guard case .application(_, let resolvedGraph) = bootstrap.route else {
            Issue.record("Valid configuration did not reach the live application route")
            return
        }
        #expect(resolvedGraph === graph)
    }

    @Test("repeated SwiftUI body evaluation cannot rebuild the graph")
    func repeatedViewEvaluationKeepsOneGraph() {
        let counter = InvocationCounter()
        let bootstrap = AppGraphBootstrap(
            config: validConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }

        for _ in 0..<50 {
            let probe = BootstrapProbe(bootstrap: bootstrap)
            _ = probe.body
        }

        #expect(counter.count == 1)
    }

    @Test("configuration transitions are deterministic")
    func deterministicTransitions() {
        let counter = InvocationCounter()
        let invalid = AppGraphBootstrap(
            config: invalidConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }
        let valid = AppGraphBootstrap(
            config: validConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }

        guard case .configurationFailure = invalid.route else {
            Issue.record("Expected invalid route")
            return
        }
        guard case .application = valid.route else {
            Issue.record("Expected valid route")
            return
        }
        #expect(counter.count == 1)
        #expect(invalidConfig().configurationIssues == invalidConfig().configurationIssues)
        #expect(validConfig().configurationIssues.isEmpty)
    }

    @Test("diagnostics failure never blocks either bootstrap outcome")
    func diagnosticsFailureDoesNotBlock() {
        let counter = InvocationCounter()
        let valid = AppGraphBootstrap(
            config: validConfig(),
            buildConfiguration: .debug,
            diagnostics: ThrowingDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }
        let invalid = AppGraphBootstrap(
            config: invalidConfig(),
            buildConfiguration: .debug,
            diagnostics: ThrowingDiagnosticsRecorder()
        ) { _ in
            counter.increment()
            return TestGraph()
        }

        guard case .application = valid.route else {
            Issue.record("Valid bootstrap was blocked by diagnostics")
            return
        }
        guard case .configurationFailure = invalid.route else {
            Issue.record("Invalid bootstrap was blocked by diagnostics")
            return
        }
        #expect(counter.count == 1)
    }

    private func validConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowTests",
            cognitoClientID: "chapterflowtestsclient12345",
            cognitoDomain: "auth.chapterflow.test"
        )
    }

    private func invalidConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.example.com",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_XXXXXXXXX",
            cognitoClientID: "XXXXXXXXXXXXXXXXXXXXXXXXXX",
            cognitoDomain: "auth.your-domain.auth.us-east-1.amazoncognito.com"
        )
    }
}

@MainActor
private struct BootstrapProbe: View {
    let bootstrap: AppGraphBootstrap<TestGraph>

    var body: some View {
        switch bootstrap.route {
        case .application:
            Text("Application")
        case .configurationFailure:
            Text("Configuration failure")
        }
    }
}

@MainActor
private final class InvocationCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private final class TestGraph {}

private struct ThrowingDiagnosticsRecorder: AppConfigurationDiagnosticsRecording {
    struct RecordingError: Error {}

    func record(_ record: AppConfigurationDiagnosticRecord) throws {
        throw RecordingError()
    }
}
