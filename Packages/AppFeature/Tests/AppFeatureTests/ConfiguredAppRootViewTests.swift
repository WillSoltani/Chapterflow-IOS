import AuthKit
import CoreKit
import Persistence
import Testing
@testable import AppFeature

@MainActor
@Suite("Configured app bootstrap")
struct ConfiguredAppRootViewTests {
    @Test("valid configuration renders preparing before storage or graph construction")
    func validConfigurationStartsWithLightweightFirstFrame() async {
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        guard case .preparing = coordinator.state else {
            Issue.record("Valid configuration did not render the preparing state")
            return
        }
        #expect(await loader.callCount == 0)
        #expect(factory.attemptCount == 0)
        #expect(factory.models.isEmpty)
    }

    @Test("invalid configuration wins before storage and never builds a graph")
    func invalidConfigurationDoesNotStartPrerequisites() async {
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(
            config: invalidConfig(),
            loader: loader,
            factory: factory
        )

        coordinator.start()

        guard case .invalidConfiguration(let record) = coordinator.state else {
            Issue.record("Invalid configuration reached another bootstrap state")
            return
        }
        #expect(record.status == .invalid)
        #expect(!record.liveServicesConstructed)
        #expect(!record.issues.isEmpty)
        #expect(await loader.callCount == 0)
        #expect(factory.attemptCount == 0)
    }

    @Test("duplicate starts keep one active load and publish exactly one graph")
    func duplicateStartsBuildOneGraph() async throws {
        let resources = try makeTestPersistenceResources()
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        for _ in 0..<50 {
            coordinator.start()
        }
        await loader.waitForCallCount(1)
        await loader.succeed(call: 1, with: resources)
        await coordinator.waitForCurrentAttempt()

        #expect(await loader.callCount == 1)
        #expect(factory.attemptCount == 1)
        #expect(factory.models.count == 1)
        #expect(factory.receivedContainer === resources.controller.container)
        guard case .ready(_, let model) = coordinator.state else {
            Issue.record("Successful prerequisites did not publish ready")
            return
        }
        #expect(model === factory.models[0])
    }

    @Test("storage failure publishes a dedicated state and no graph")
    func storageFailurePublishesNoGraph() async {
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.fail(call: 1)
        await coordinator.waitForCurrentAttempt()

        guard case .storageUnavailable(let failure) = coordinator.state else {
            Issue.record("Storage failure did not reach its dedicated state")
            return
        }
        #expect(failure.supportCode == "CF-BOOT-STORAGE-001")
        #expect(factory.attemptCount == 0)
        #expect(factory.models.isEmpty)
    }

    @Test("retry starts one fresh attempt and can recover to ready")
    func retryIsAtomicAndRecoverable() async throws {
        let resources = try makeTestPersistenceResources()
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.fail(call: 1)
        await coordinator.waitForCurrentAttempt()

        for _ in 0..<20 {
            coordinator.retry()
        }
        await loader.waitForCallCount(2)
        await loader.succeed(call: 2, with: resources)
        await coordinator.waitForCurrentAttempt()

        #expect(await loader.callCount == 2)
        #expect(factory.attemptCount == 1)
        guard case .ready = coordinator.state else {
            Issue.record("Retry did not recover to ready")
            return
        }
    }

    @Test("required session failure publishes no graph")
    func sessionFailurePublishesNoGraph() async throws {
        let resources = try makeTestPersistenceResources()
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory(shouldFail: true)
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.succeed(call: 1, with: resources)
        await coordinator.waitForCurrentAttempt()

        guard case .sessionConfigurationFailed(let failure) = coordinator.state else {
            Issue.record("Session failure did not reach its dedicated state")
            return
        }
        #expect(failure.supportCode == "CF-BOOT-SESSION-001")
        #expect(factory.attemptCount == 1)
        #expect(factory.models.isEmpty)
    }

    @Test("superseded attempt cannot overwrite the newer ready graph")
    func staleCompletionCannotWin() async throws {
        let oldResources = try makeTestPersistenceResources()
        let currentResources = try makeTestPersistenceResources()
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        coordinator.restartActiveAttempt()
        await loader.waitForCallCount(2)

        await loader.succeed(call: 2, with: currentResources)
        await coordinator.waitForCurrentAttempt()
        guard case .ready(_, let currentModel) = coordinator.state else {
            Issue.record("Replacement attempt did not become ready")
            return
        }

        // The controlled loader deliberately ignores task cancellation until
        // resumed, exercising the generation guard rather than timing luck.
        await loader.succeed(call: 1, with: oldResources)
        await Task.yield()

        guard case .ready(_, let finalModel) = coordinator.state else {
            Issue.record("Stale completion replaced ready with another state")
            return
        }
        #expect(finalModel === currentModel)
        #expect(factory.attemptCount == 1)
        #expect(factory.receivedContainer === currentResources.controller.container)
    }

    @Test("explicit cancellation remains preparing instead of becoming user-facing failure")
    func cancellationIsNotFailure() async {
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        coordinator.cancel()

        guard case .preparing = coordinator.state else {
            Issue.record("Cancellation was converted into a terminal failure")
            return
        }
        #expect(factory.attemptCount == 0)
    }

    @Test("failure state carries fixed privacy-safe support codes only")
    func failureStateIsPrivacySafe() {
        let storage = AppBootstrapStorageFailure()
        let session = AppBootstrapSessionFailure()

        #expect(storage.supportCode == "CF-BOOT-STORAGE-001")
        #expect(session.supportCode == "CF-BOOT-SESSION-001")
        #expect(String(reflecting: storage) == "AppFeature.AppBootstrapStorageFailure()")
        #expect(String(reflecting: session) == "AppFeature.AppBootstrapSessionFailure()")
    }

    @Test("diagnostics recording failure cannot block invalid configuration")
    func diagnosticsFailureDoesNotBlockInvalidState() {
        let coordinator = AppBootstrapCoordinator(
            config: invalidConfig(),
            buildConfiguration: .debug,
            diagnostics: ThrowingDiagnosticsRecorder(),
            persistenceLoader: ControlledPersistenceLoader(),
            graphFactory: RecordingGraphFactory()
        )

        guard case .invalidConfiguration = coordinator.state else {
            Issue.record("Best-effort diagnostics blocked bootstrap")
            return
        }
    }

    private func makeCoordinator(
        config: AppConfig? = nil,
        loader: ControlledPersistenceLoader,
        factory: RecordingGraphFactory
    ) -> AppBootstrapCoordinator {
        AppBootstrapCoordinator(
            config: config ?? validConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: loader,
            graphFactory: factory
        )
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

private actor ControlledPersistenceLoader: AppPersistenceLoading {
    private struct Waiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var pending: [Int: CheckedContinuation<AppPersistenceResources, any Error>] = [:]
    private var waiters: [Waiter] = []
    private(set) var callCount = 0

    func load() async throws -> AppPersistenceResources {
        callCount += 1
        let call = callCount
        resumeSatisfiedWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
        }
    }

    func waitForCallCount(_ target: Int) async {
        guard callCount < target else { return }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(target: target, continuation: continuation))
        }
    }

    func succeed(call: Int, with resources: AppPersistenceResources) {
        pending.removeValue(forKey: call)?.resume(returning: resources)
    }

    func fail(call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: ControlledBootstrapError())
    }

    private func resumeSatisfiedWaiters() {
        while let index = waiters.firstIndex(where: { $0.target <= callCount }) {
            waiters.remove(at: index).continuation.resume()
        }
    }
}

@MainActor
private final class RecordingGraphFactory: AppGraphFactory {
    private let shouldFail: Bool
    private(set) var attemptCount = 0
    private(set) var models: [AppModel] = []
    private(set) var receivedContainer: AnyObject?

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func makeConfiguredGraph(
        config: ValidatedAppConfig,
        persistence: AppPersistenceResources
    ) throws -> AppModel {
        attemptCount += 1
        receivedContainer = persistence.controller.container
        if shouldFail {
            throw ControlledBootstrapError()
        }

        let authService = AuthService(config: config.value)
        let model = AppModel(
            config: config,
            persistence: persistence,
            authService: authService,
            session: SessionManager(authService: authService)
        )
        models.append(model)
        return model
    }
}

private struct ControlledBootstrapError: Error {}

private struct ThrowingDiagnosticsRecorder: AppConfigurationDiagnosticsRecording {
    func record(_ record: AppConfigurationDiagnosticRecord) throws {
        throw ControlledBootstrapError()
    }
}
