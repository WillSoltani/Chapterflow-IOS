import Foundation

/// Value-free failure categories for opening required account-local storage.
///
/// Underlying filesystem and SwiftData errors do not cross this boundary, and
/// no category carries a path or account-derived value.
public enum AccountPersistenceLoadFailure: Error, Equatable, Sendable {
    /// The supplied opaque namespace was not a safe, single path component.
    case invalidStorageNamespace
    /// The required account directory could not be created at its configured location.
    case requiredAccountDirectory
    /// The account's SwiftData store could not be opened or migrated.
    case persistentStoreOpenOrMigration
    /// The account's required download directory could not be opened.
    case requiredFileStore
}

/// Required durable resources belonging to exactly one opaque account namespace.
///
/// Construction is kept inside this package so a live resource bundle cannot be
/// assembled with a namespace unrelated to the paths selected by the loader.
public struct AccountPersistenceResources: Sendable {
    /// Opaque, stable storage namespace used to select this resource bundle.
    public let storageNamespace: String
    /// Account-local SwiftData controller using the shipping V8 migration plan.
    public let controller: PersistenceController
    /// Account-local download file store.
    public let downloadFileStore: FileStore

    fileprivate init(
        storageNamespace: String,
        controller: PersistenceController,
        downloadFileStore: FileStore
    ) {
        self.storageNamespace = storageNamespace
        self.controller = controller
        self.downloadFileStore = downloadFileStore
    }

    /// Proves whether this bundle belongs to a caller's expected namespace.
    public func matches(storageNamespace: String) -> Bool {
        self.storageNamespace == storageNamespace
    }
}

/// Boundary used by session composition to open one account's required storage.
public protocol AccountPersistenceLoading: Sendable {
    /// Opens the resource bundle for one opaque, stable storage namespace.
    func load(storageNamespace: String) async throws -> AccountPersistenceResources
}

/// Opens account-local SwiftData and download resources without fallback.
///
/// Production storage lives at:
/// `Application Support/com.chapterflow/accounts/<namespace>/`
/// with `ChapterFlow.private.store` and `Downloads` beneath that directory.
public struct DefaultAccountPersistenceLoader: AccountPersistenceLoading {
    private let accountsRootProvider: @Sendable () throws -> URL

    /// Creates the production loader rooted in Application Support.
    public init() {
        accountsRootProvider = Self.productionAccountsRoot
    }

    /// Creates a loader rooted at an explicit directory for deterministic tests.
    init(accountsRoot: URL) {
        accountsRootProvider = { accountsRoot }
    }

    // SwiftData and filesystem setup are synchronous. @concurrent prevents that
    // work from inheriting a caller such as MainActor.
    // swiftlint:disable:next async_without_await
    @concurrent
    public func load(storageNamespace: String) async throws -> AccountPersistenceResources {
        guard Self.isValid(storageNamespace: storageNamespace) else {
            throw AccountPersistenceLoadFailure.invalidStorageNamespace
        }

        let accountsRoot: URL
        do {
            accountsRoot = try accountsRootProvider()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountPersistenceLoadFailure.requiredAccountDirectory
        }

        try Task.checkCancellation()

        let namespaceRoot = accountsRoot.appending(
            path: storageNamespace,
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(
                at: namespaceRoot,
                withIntermediateDirectories: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountPersistenceLoadFailure.requiredAccountDirectory
        }

        try Task.checkCancellation()

        let privateStoreURL = namespaceRoot.appending(path: "ChapterFlow.private.store")
        let controller: PersistenceController
        do {
            controller = try PersistenceController.makeDefault(
                storage: .privateStore(privateStoreURL)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountPersistenceLoadFailure.persistentStoreOpenOrMigration
        }

        try Task.checkCancellation()

        let fileStore: FileStore
        do {
            fileStore = try FileStore(
                root: namespaceRoot.appending(path: "Downloads", directoryHint: .isDirectory)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountPersistenceLoadFailure.requiredFileStore
        }

        try Task.checkCancellation()

        return AccountPersistenceResources(
            storageNamespace: storageNamespace,
            controller: controller,
            downloadFileStore: fileStore
        )
    }

    private static func productionAccountsRoot() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appending(path: "com.chapterflow", directoryHint: .isDirectory)
            .appending(path: "accounts", directoryHint: .isDirectory)
    }

    fileprivate static func isValid(storageNamespace: String) -> Bool {
        guard !storageNamespace.isEmpty, storageNamespace.utf8.count <= 128 else {
            return false
        }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        return storageNamespace.unicodeScalars.allSatisfy(allowed.contains)
    }
}

#if DEBUG
/// Deterministic account-loader seam for tests and hermetic previews.
///
/// Each namespace receives its own in-memory SwiftData container and temporary
/// download root. Repeated loads return the same resource identity, mirroring
/// the one-scope-per-account lifetime expected from production composition.
public actor InMemoryAccountPersistenceLoader: AccountPersistenceLoading {
    private let root: URL
    private var resourcesByNamespace: [String: AccountPersistenceResources] = [:]

    public init(root: URL) {
        self.root = root
    }

    public func load(storageNamespace: String) async throws -> AccountPersistenceResources {
        if let resources = resourcesByNamespace[storageNamespace] {
            return resources
        }

        guard DefaultAccountPersistenceLoader.isValid(storageNamespace: storageNamespace) else {
            throw AccountPersistenceLoadFailure.invalidStorageNamespace
        }

        let controller: PersistenceController
        do {
            controller = try PersistenceController.makeDefault(storage: .inMemory)
        } catch {
            throw AccountPersistenceLoadFailure.persistentStoreOpenOrMigration
        }

        let fileStore: FileStore
        do {
            fileStore = try FileStore(
                root: root
                    .appending(path: storageNamespace, directoryHint: .isDirectory)
                    .appending(path: "Downloads", directoryHint: .isDirectory)
            )
        } catch {
            throw AccountPersistenceLoadFailure.requiredFileStore
        }

        let resources = AccountPersistenceResources(
            storageNamespace: storageNamespace,
            controller: controller,
            downloadFileStore: fileStore
        )
        resourcesByNamespace[storageNamespace] = resources
        return resources
    }
}
#endif
