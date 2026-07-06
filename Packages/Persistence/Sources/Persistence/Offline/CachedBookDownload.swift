import Foundation
import SwiftData

/// The download status of a book.
public enum BookDownloadStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case downloading
    case downloaded
    case failed
}

/// Tracks the download state of a single book for a given user.
///
/// Stored in V7 of the schema; created when a download starts and updated as
/// chapters and audio segments are stored locally.
@Model
public final class CachedBookDownload {
    /// Composite unique key: "userId:bookId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    /// Book title — stored for display without re-fetching the manifest.
    public var title: String
    public var statusRaw: String
    /// Total on-disk bytes for JSON content + audio files (updated as download proceeds).
    public var totalBytes: Int64
    /// Number of chapters in the manifest.
    public var chapterCount: Int
    /// How many chapters have had their content + quiz stored.
    public var downloadedChapterCount: Int
    /// Total audio segment count across all chapters.
    public var audioSegmentCount: Int
    /// How many audio segments have been stored locally.
    public var downloadedAudioSegmentCount: Int
    /// When the download was initiated.
    public var startedAt: Date
    /// When the download finished successfully; nil if incomplete.
    public var completedAt: Date?
    /// Last error message (nil when status is not `.failed`).
    public var errorMessage: String?

    public var status: BookDownloadStatus {
        get { BookDownloadStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    /// 0.0–1.0 based on chapter + audio progress.
    public var fractionCompleted: Double {
        let total = chapterCount + audioSegmentCount
        guard total > 0 else { return 0 }
        let done = downloadedChapterCount + downloadedAudioSegmentCount
        return Double(done) / Double(total)
    }

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        title: String,
        startedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.title = title
        self.statusRaw = BookDownloadStatus.downloading.rawValue
        self.totalBytes = 0
        self.chapterCount = 0
        self.downloadedChapterCount = 0
        self.audioSegmentCount = 0
        self.downloadedAudioSegmentCount = 0
        self.startedAt = startedAt
    }

    public static func makeRowId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }
}
