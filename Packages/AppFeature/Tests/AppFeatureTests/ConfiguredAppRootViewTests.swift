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

    @Test(
        "typed storage failures publish their closed category and no graph",
        arguments: [
            AppPersistenceLoadFailure.persistentStoreOpenOrMigration,
            AppPersistenceLoadFailure.requiredFileStore,
        ]
    )
    func typedStorageFailurePublishesNoGraph(
        _ injectedFailure: AppPersistenceLoadFailure
    ) async {
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(loader: loader, factory: factory)

        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.fail(call: 1, with: injectedFailure)
        await coordinator.waitForCurrentAttempt()

        guard case .storageUnavailable(let failure) = coordinator.state else {
            Issue.record("Storage failure did not reach its dedicated state")
            return
        }
        switch injectedFailure {
        case .persistentStoreOpenOrMigration:
            #expect(failure.category == .persistentStoreOpenOrMigration)
            #expect(failure.supportCode == .persistentStoreOpenOrMigration)
        case .requiredFileStore:
            #expect(failure.category == .requiredFileStore)
            #expect(failure.supportCode == .requiredFileStore)
        }
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
        await loader.fail(call: 1, with: AppPersistenceLoadFailure.requiredFileStore)
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
        await loader.fail(call: 1, with: CancellationError())
        await Task.yield()

        guard case .preparing = coordinator.state else {
            Issue.record("Cancellation was converted into a terminal failure")
            return
        }
        #expect(factory.attemptCount == 0)
    }

    @Test("loader-originated cancellation is not mistaken for coordinator cancellation")
    func unexpectedCancellationIsStorageFailure() async {
        let loader = ControlledPersistenceLoader()
        let coordinator = makeCoordinator(
            loader: loader,
            factory: RecordingGraphFactory()
        )

        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.fail(call: 1, with: CancellationError())
        await coordinator.waitForCurrentAttempt()

        guard case .storageUnavailable(let failure) = coordinator.state else {
            Issue.record("Unexpected loader cancellation stranded bootstrap")
            return
        }
        #expect(failure.category == .unavailable)
        #expect(failure.supportCode == .unavailable)
    }

    @Test("protected data waits without opening storage and resumes exactly once")
    func protectedDataWaitRecoversAutomatically() async throws {
        let resources = try makeTestPersistenceResources()
        let availability = ControlledProtectedDataAvailability(isAvailable: false)
        let recorder = RecordingBootstrapPhaseRecorder()
        let loader = ControlledPersistenceLoader()
        let factory = RecordingGraphFactory()
        let coordinator = makeCoordinator(
            loader: loader,
            factory: factory,
            protectedDataAvailability: availability,
            phaseRecorder: recorder
        )

        coordinator.markFirstLaunchViewAvailable()
        for _ in 0..<25 {
            coordinator.start()
        }
        await availability.waitForCallCount(1)

        guard case .waitingForProtectedData(let waitingFailure) = coordinator.state else {
            Issue.record("Unavailable protected data did not enter its waiting state")
            return
        }
        #expect(waitingFailure.category == .protectedDataUnavailable)
        #expect(waitingFailure.supportCode == .protectedDataUnavailable)
        #expect(!waitingFailure.isRetryMeaningful)
        #expect(await loader.callCount == 0)
        #expect(availability.waitCallCount == 1)

        availability.resume(call: 1, makingAvailable: true)
        await loader.waitForCallCount(1)
        await loader.succeed(call: 1, with: resources)
        await coordinator.waitForCurrentAttempt()

        guard case .ready = coordinator.state else {
            Issue.record("Protected-data notification did not resume bootstrap")
            return
        }
        #expect(await loader.callCount == 1)
        #expect(factory.attemptCount == 1)
        #expect(recorder.phases == [
            .bootstrapStarted,
            .firstLaunchViewAvailable,
            .protectedDataWaiting,
            .protectedDataBecameAvailable,
            .persistenceOpenStarted,
            .persistenceOpenCompleted,
            .requiredSessionSetupStarted,
            .requiredSessionSetupCompleted,
            .readyPublished,
        ])
    }

    @Test("superseded protected-data observer cannot start stale storage work")
    func staleProtectedDataCallbackCannotWin() async throws {
        let resources = try makeTestPersistenceResources()
        let availability = ControlledProtectedDataAvailability(isAvailable: false)
        let loader = ControlledPersistenceLoader()
        let coordinator = makeCoordinator(
            loader: loader,
            factory: RecordingGraphFactory(),
            protectedDataAvailability: availability
        )

        coordinator.start()
        await availability.waitForCallCount(1)
        coordinator.restartActiveAttempt()
        await availability.waitForCallCount(2)

        availability.resume(call: 1, makingAvailable: true)
        await Task.yield()
        #expect(await loader.callCount == 0)
        guard case .waitingForProtectedData = coordinator.state else {
            Issue.record("Stale protected-data callback replaced the current wait")
            return
        }

        availability.resume(call: 2, makingAvailable: true)
        await loader.waitForCallCount(1)
        await loader.succeed(call: 1, with: resources)
        await coordinator.waitForCurrentAttempt()

        #expect(await loader.callCount == 1)
        guard case .ready = coordinator.state else {
            Issue.record("Current protected-data callback did not resume bootstrap")
            return
        }
    }

    @Test("protected-data observation is cancelled when bootstrap deinitializes")
    func protectedDataObserverCannotOutliveCoordinator() async {
        let availability = CancellationTrackingAvailability()
        var coordinator: AppBootstrapCoordinator? = makeCoordinator(
            loader: ControlledPersistenceLoader(),
            factory: RecordingGraphFactory(),
            protectedDataAvailability: availability
        )
        let weakCoordinator = WeakReference(coordinator)

        coordinator?.start()
        await availability.waitForStart()
        guard case .waitingForProtectedData = coordinator?.state else {
            Issue.record("Bootstrap did not own a protected-data observation")
            return
        }

        coordinator = nil
        #expect(weakCoordinator.value == nil)
        await availability.waitForCancellation()
        #expect(availability.cancellationCount == 1)
    }

    @Test("storage failure while protection is unavailable becomes an automatic wait")
    func lockDuringStorageFailureWaitsInsteadOfOfferingRetry() async throws {
        let resources = try makeTestPersistenceResources()
        let availability = ControlledProtectedDataAvailability(isAvailable: true)
        let loader = ControlledPersistenceLoader()
        let coordinator = makeCoordinator(
            loader: loader,
            factory: RecordingGraphFactory(),
            protectedDataAvailability: availability
        )

        coordinator.start()
        await loader.waitForCallCount(1)
        availability.setAvailable(false)
        await loader.fail(
            call: 1,
            with: AppPersistenceLoadFailure.persistentStoreOpenOrMigration
        )
        await coordinator.waitForCurrentAttempt()
        await availability.waitForCallCount(1)

        guard case .waitingForProtectedData = coordinator.state else {
            Issue.record("Protected-data loss was presented as store corruption")
            return
        }

        availability.resume(call: 1, makingAvailable: true)
        await loader.waitForCallCount(2)
        await loader.succeed(call: 2, with: resources)
        await coordinator.waitForCurrentAttempt()
        guard case .ready = coordinator.state else {
            Issue.record("Bootstrap did not recover after protected data returned")
            return
        }
    }

    @Test("phase recorder failure never blocks the launch state machine")
    func phaseRecorderFailureIsBestEffort() async throws {
        let resources = try makeTestPersistenceResources()
        let loader = ControlledPersistenceLoader()
        let recorder = RecordingBootstrapPhaseRecorder(shouldThrow: true)
        let coordinator = makeCoordinator(
            loader: loader,
            factory: RecordingGraphFactory(),
            phaseRecorder: recorder
        )

        coordinator.markFirstLaunchViewAvailable()
        coordinator.start()
        await loader.waitForCallCount(1)
        await loader.succeed(call: 1, with: resources)
        await coordinator.waitForCurrentAttempt()

        guard case .ready = coordinator.state else {
            Issue.record("Instrumentation failure blocked ready publication")
            return
        }
        #expect(recorder.phases.last == .readyPublished)
    }

    @Test("invalid configuration has a deterministic terminal phase order")
    func invalidConfigurationPhaseOrder() {
        let recorder = RecordingBootstrapPhaseRecorder()
        let coordinator = AppBootstrapCoordinator(
            config: invalidConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: ControlledPersistenceLoader(),
            graphFactory: RecordingGraphFactory(),
            phaseRecorder: recorder
        )

        coordinator.markFirstLaunchViewAvailable()

        #expect(recorder.phases == [
            .bootstrapStarted,
            .invalidConfigurationFailed,
            .firstLaunchViewAvailable,
        ])
    }

    @Test("failure state carries fixed privacy-safe support codes only")
    func failureStateIsPrivacySafe() {
        let storage = AppBootstrapStorageFailure(category: .persistentStoreOpenOrMigration)
        let session = AppBootstrapSessionFailure()

        #expect(storage.supportCode == .persistentStoreOpenOrMigration)
        #expect(storage.supportCode.rawValue == "CF-BOOT-STORAGE-STORE-001")
        #expect(storage.isRetryMeaningful)
        #expect(!AppBootstrapStorageFailure(
            category: .protectedDataUnavailable
        ).isRetryMeaningful)
        #expect(session.supportCode == "CF-BOOT-SESSION-001")
        #expect(!String(reflecting: storage).contains("/"))
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
        factory: RecordingGraphFactory,
        protectedDataAvailability: (any ProtectedDataAvailabilityProviding)? = nil,
        phaseRecorder: (any AppBootstrapPhaseRecording)? = nil
    ) -> AppBootstrapCoordinator {
        AppBootstrapCoordinator(
            config: config ?? validConfig(),
            buildConfiguration: .debug,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: loader,
            graphFactory: factory,
            protectedDataAvailability: protectedDataAvailability
                ?? ControlledProtectedDataAvailability(isAvailable: true),
            phaseRecorder: phaseRecorder ?? NoopAppBootstrapPhaseRecorder()
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
