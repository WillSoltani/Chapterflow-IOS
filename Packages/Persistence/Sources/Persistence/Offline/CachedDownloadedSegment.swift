import Foundation
import SwiftData

/// Records a single audio segment file that has been downloaded and stored locally.
///
/// Stored in V7 of the schema. The actual audio file lives in the FileStore under
/// the key `audio_<segmentId>`. Querying by `bookId` lets the DownloadManager
/// identify which segments still need downloading when resuming an interrupted run.
@Model
public final class CachedDownloadedSegment {
    /// Stable segment identifier — also the FileStore file key prefix.
    @Attribute(.unique) public var segmentId: String
    public var bookId: String
    public var chapterNumber: Int
    public var userId: String
    public var fileSize: Int64
    public var downloadedAt: Date

    public init(
        segmentId: String,
        bookId: String,
        chapterNumber: Int,
        userId: String,
        fileSize: Int64,
        downloadedAt: Date = Date()
    ) {
        self.segmentId = segmentId
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.userId = userId
        self.fileSize = fileSize
        self.downloadedAt = downloadedAt
    }

    /// The FileStore key used to store/retrieve the audio file for this segment.
    public static func fileStoreKey(segmentId: String) -> String {
        "audio_\(segmentId)"
    }
}
