import Foundation

/// Metadata about a fully-downloaded book.
public struct DownloadedBookInfo: Sendable, Identifiable, Equatable {
    public let id: String           // bookId
    public let bookId: String
    public let title: String
    public let totalBytes: Int64
    public let downloadedAt: Date?

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public init(bookId: String, title: String, totalBytes: Int64, downloadedAt: Date?) {
        self.id = bookId
        self.bookId = bookId
        self.title = title
        self.totalBytes = totalBytes
        self.downloadedAt = downloadedAt
    }
}

/// Exposes read-only download inventory and deletion for UI/Settings layers
/// that don't need the full `DownloadManager` (no network dependency).
public protocol DownloadInfoProviding: AnyObject, Sendable {
    /// Returns info about all fully-downloaded books for `userId`.
    func downloadedBooks(userId: String) async -> [DownloadedBookInfo]
    /// Aggregated on-disk bytes for all downloads owned by `userId`.
    func totalUsedBytes(userId: String) async -> Int64
    /// Whether the given book is fully downloaded for `userId`.
    func isDownloaded(bookId: String, userId: String) async -> Bool
    /// Deletes the download for `bookId`, removing content from SwiftData and
    /// audio files from the FileStore.
    func deleteBookDownload(bookId: String, userId: String) async throws
    /// Deletes all downloads for `userId`.
    func deleteAllBookDownloads(userId: String) async throws
}
