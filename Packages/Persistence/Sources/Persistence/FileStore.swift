import Foundation

/// A directory-scoped file store for downloaded audio and content blobs.
///
/// Files live under Application Support (or the App Group container) and are excluded
/// from iCloud backup — cached, re-downloadable content should not consume the user's
/// backup quota.
public struct FileStore: Sendable {
    /// The root directory that holds this store's files.
    public let root: URL

    /// Wraps an explicit root directory, creating it and marking it backup-excluded.
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.excludeFromBackup(root)
    }

    /// A store rooted at `Application Support/ChapterFlow/<subdirectory>`.
    public static func applicationSupport(subdirectory: String = "Downloads") throws -> FileStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appending(path: "ChapterFlow").appending(path: subdirectory)
        return try FileStore(root: root)
    }

    /// A store rooted in the shared App Group container (readable by extensions).
    public static func appGroup(subdirectory: String = "Downloads") throws -> FileStore {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) else {
            throw PersistenceError.appGroupUnavailable
        }
        let root = base.appending(path: "Downloads").appending(path: subdirectory)
        return try FileStore(root: root)
    }

    /// The on-disk URL for a named file (does not check existence).
    public func url(for name: String) -> URL {
        root.appending(path: name)
    }

    /// Whether a file with `name` exists.
    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// Atomically writes `data` to `name` and returns its URL.
    @discardableResult
    public func write(_ data: Data, named name: String) throws -> URL {
        let fileURL = url(for: name)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Reads the file `name`, throwing ``PersistenceError/notFound`` if absent.
    public func read(named name: String) throws -> Data {
        let fileURL = url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.notFound
        }
        return try Data(contentsOf: fileURL)
    }

    /// Removes the file `name` (no-op if absent).
    public func remove(named name: String) throws {
        let fileURL = url(for: name)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Marks `url` as excluded from iCloud/iTunes backup.
    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
