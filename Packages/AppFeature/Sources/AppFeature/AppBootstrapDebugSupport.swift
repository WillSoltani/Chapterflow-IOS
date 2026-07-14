#if DEBUG
import CoreKit
import Persistence

/// Hermetic XCUITest-only bootstrap modes. The app host activates these only
/// when both the fixture server and typed hermetic configuration are enabled.
public enum AppBootstrapDebugMode: Sendable {
    case live
    case suspendStorage
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

        switch debugMode {
        case .live:
            loader = hermeticLoader
            graphFactory = LiveAppGraphFactory()
        case .suspendStorage:
            loader = DebugSuspendingPersistenceLoader()
            graphFactory = LiveAppGraphFactory()
        case .failStorageOnce:
            loader = DebugFailOncePersistenceLoader(live: hermeticLoader)
            graphFactory = LiveAppGraphFactory()
        case .failSessionConfiguration:
            loader = hermeticLoader
            graphFactory = DebugFailingSessionGraphFactory()
        }

        self.init(
            config: config,
            buildConfiguration: buildConfiguration,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: loader,
            graphFactory: graphFactory
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
            throw DebugBootstrapError()
        }
        return try await live.load()
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
