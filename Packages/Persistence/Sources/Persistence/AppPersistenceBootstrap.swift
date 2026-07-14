import Foundation

/// Value-free classification of failures at the required persistence bootstrap
/// boundaries. Raw SwiftData and filesystem errors never cross this API.
public enum AppPersistenceLoadFailure: Error, Equatable, Sendable {
    /// The current SwiftData store could not be opened or migrated.
    case persistentStoreOpenOrMigration
    /// The required download file store could not be opened at its configured root.
    case requiredFileStore
}

/// Required durable resources for the live application graph.
///
/// The composition root receives this value only after both SwiftData and the
/// download directory have opened successfully. Production never substitutes an
/// in-memory container or a different directory when either operation fails.
public struct AppPersistenceResources: Sendable {
    public let controller: PersistenceController
    public let downloadFileStore: FileStore

    public init(controller: PersistenceController, downloadFileStore: FileStore) {
        self.controller = controller
        self.downloadFileStore = downloadFileStore
    }
}

/// Asynchronous boundary used by app bootstrap to open required local storage.
public protocol AppPersistenceLoading: Sendable {
    func load() async throws -> AppPersistenceResources
}

/// Opens the production SwiftData container and download directory away from
/// the caller's actor. Errors are deliberately propagated to the bootstrap
/// state machine so the UI can offer an honest retry surface.
public struct DefaultAppPersistenceLoader: AppPersistenceLoading {
    private let storage: StorageMode
    private let downloadRoot: URL?
    private let persistenceFactory: @Sendable (StorageMode) throws -> PersistenceController
    private let fileStoreFactory: @Sendable (URL?) throws -> FileStore

    public init() {
        storage = .appGroup
        downloadRoot = nil
        persistenceFactory = Self.makePersistenceController
        fileStoreFactory = Self.makeFileStore
    }

    init(storage: StorageMode, downloadRoot: URL?) {
        self.storage = storage
        self.downloadRoot = downloadRoot
        persistenceFactory = Self.makePersistenceController
        fileStoreFactory = Self.makeFileStore
    }

    init(
        storage: StorageMode,
        downloadRoot: URL?,
        persistenceFactory: @escaping @Sendable (StorageMode) throws -> PersistenceController,
        fileStoreFactory: @escaping @Sendable (URL?) throws -> FileStore
    ) {
        self.storage = storage
        self.downloadRoot = downloadRoot
        self.persistenceFactory = persistenceFactory
        self.fileStoreFactory = fileStoreFactory
    }

    // This method is intentionally async without internal suspension: @concurrent
    // guarantees that synchronous SwiftData and filesystem work does not inherit
    // the caller's actor.
    // swiftlint:disable:next async_without_await
    @concurrent
    public func load() async throws -> AppPersistenceResources {
        let controller: PersistenceController
        do {
            controller = try persistenceFactory(storage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppPersistenceLoadFailure.persistentStoreOpenOrMigration
        }

        try Task.checkCancellation()

        let fileStore: FileStore
        do {
            fileStore = try fileStoreFactory(downloadRoot)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppPersistenceLoadFailure.requiredFileStore
        }

        try Task.checkCancellation()

        return AppPersistenceResources(
            controller: controller,
            downloadFileStore: fileStore
        )
    }

    private static func makePersistenceController(
        storage: StorageMode
    ) throws -> PersistenceController {
        try PersistenceController.makeDefault(storage: storage)
    }

    private static func makeFileStore(downloadRoot: URL?) throws -> FileStore {
        if let downloadRoot {
            return try FileStore(root: downloadRoot)
        }
        return try FileStore.applicationSupport(subdirectory: "Downloads")
    }
}

#if DEBUG
public extension DefaultAppPersistenceLoader {
    /// Explicitly in-memory SwiftData and process-local files for hermetic UI
    /// tests. This factory is absent from non-Debug builds and is selected by
    /// the app host only behind its paired stub-server and hermetic-config gate.
    static func hermeticTestStorage() -> Self {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "cf-hermetic-bootstrap-\(UUID().uuidString)"
        )
        return Self(storage: .inMemory, downloadRoot: root)
    }
}
#endif
