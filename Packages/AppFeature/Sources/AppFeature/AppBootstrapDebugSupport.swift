#if DEBUG
import CoreKit
import Persistence

/// Hermetic XCUITest-only bootstrap modes. The app host activates these only
/// when both the fixture server and typed hermetic configuration are enabled.
public enum AppBootstrapDebugMode: Sendable {
    case live
    case suspendStorage
    case waitForProtectedData
    case failStorageOnce
    case failSessionConfiguration
}

public extension AppBootstrapCoordinator {
    convenience init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration,
        debugMode: AppBootstrapDebugMode
    ) {
        let hermeticLoader = DefaultAppPersistenceLoader.hermeticTestStorage()
        let loader: any AppPersistenceLoading
        let graphFactory: any AppGraphFactory
        let protectedDataAvailability: any ProtectedDataAvailabilityProviding

        switch debugMode {
        case .live:
            loader = hermeticLoader
            graphFactory = LiveAppGraphFactory()
            protectedDataAvailability = DebugAvailableProtectedDataProvider()
        case .suspendStorage:
            loader = DebugSuspendingPersistenceLoader()
            graphFactory = LiveAppGraphFactory()
            protectedDataAvailability = DebugAvailableProtectedDataProvider()
        case .waitForProtectedData:
            loader = hermeticLoader
            graphFactory = LiveAppGraphFactory()
            protectedDataAvailability = DebugDelayedProtectedDataProvider()
        case .failStorageOnce:
            loader = DebugFailOncePersistenceLoader(live: hermeticLoader)
            graphFactory = LiveAppGraphFactory()
            protectedDataAvailability = DebugAvailableProtectedDataProvider()
        case .failSessionConfiguration:
            loader = hermeticLoader
            graphFactory = DebugFailingSessionGraphFactory()
            protectedDataAvailability = DebugAvailableProtectedDataProvider()
        }

        self.init(
            config: config,
            buildConfiguration: buildConfiguration,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: loader,
            graphFactory: graphFactory,
            protectedDataAvailability: protectedDataAvailability
        )
    }
}

private struct DebugBootstrapError: Error {}

private actor DebugSuspendingPersistenceLoader: AppPersistenceLoading {
    func load() async throws -> AppPersistenceResources {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
    }
}

private actor DebugFailOncePersistenceLoader: AppPersistenceLoading {
    private let live: DefaultAppPersistenceLoader
    private var hasFailed = false

    init(live: DefaultAppPersistenceLoader) {
        self.live = live
    }

    func load() async throws -> AppPersistenceResources {
        if !hasFailed {
            hasFailed = true
            throw AppPersistenceLoadFailure.persistentStoreOpenOrMigration
        }
        return try await live.load()
    }
}

@MainActor
private final class DebugAvailableProtectedDataProvider: ProtectedDataAvailabilityProviding {
    var isAvailable: Bool { true }

    func waitUntilAvailable() async {}
}

@MainActor
private final class DebugDelayedProtectedDataProvider: ProtectedDataAvailabilityProviding {
    private(set) var isAvailable = false

    func waitUntilAvailable() async {
        // Long enough for XCUITest to observe the waiting surface after process
        // launch and accessibility-session setup; still bounded well inside its
        // recovery assertion timeout.
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled else { return }
        isAvailable = true
    }
}

@MainActor
private struct DebugFailingSessionGraphFactory: AppGraphFactory {
    func makeConfiguredGraph(
        config _: ValidatedAppConfig,
        persistence _: AppPersistenceResources
    ) throws -> AppModel {
        throw DebugBootstrapError()
    }
}
#endif
