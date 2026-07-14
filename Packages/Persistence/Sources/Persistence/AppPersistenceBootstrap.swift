import Foundation

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

    public init() {
        storage = .appGroup
        downloadRoot = nil
    }

    init(storage: StorageMode, downloadRoot: URL?) {
        self.storage = storage
        self.downloadRoot = downloadRoot
    }

    // This method is intentionally async without internal suspension: @concurrent
    // guarantees that synchronous SwiftData and filesystem work does not inherit
    // the caller's actor.
    // swiftlint:disable:next async_without_await
    @concurrent
    public func load() async throws -> AppPersistenceResources {
        let controller = try PersistenceController.makeDefault(storage: storage)
        let fileStore: FileStore
        if let downloadRoot {
            fileStore = try FileStore(root: downloadRoot)
        } else {
            fileStore = try FileStore.applicationSupport(subdirectory: "Downloads")
        }
        return AppPersistenceResources(
            controller: controller,
            downloadFileStore: fileStore
        )
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
