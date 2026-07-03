import Foundation
import Models

/// Data access contract for the P6.2 audio narration feature.
///
/// Concrete implementations:
/// - ``LiveAudioRepository`` — calls the ChapterFlow REST API.
/// - ``FakeAudioRepository`` — in-memory fake for previews and tests.
public protocol AudioRepository: Sendable {

    /// Fetches the personalised narration plan for a chapter.
    ///
    /// `GET /book/books/{bookId}/chapters/{chapterNumber}/audio`
    ///
    /// Call again to refresh presigned URLs after a 403/expiry error.
    func fetchPlan(bookId: String, chapterNumber: Int) async throws -> AudioNarrationPlan

    /// Downloads a single segment asset to a local file and returns its URL.
    ///
    /// - Parameters:
    ///   - remoteURL: Presigned source URL (call after fetching a fresh plan).
    ///   - segmentId: Stable identifier used as the local filename.
    ///   - directory: Directory to store the file in.
    /// - Returns: The local file URL.
    func downloadSegment(
        remoteURL: URL,
        segmentId: String,
        to directory: URL
    ) async throws -> URL

    /// Returns the local file URL for a downloaded segment, or `nil` if not cached.
    /// Implemented as `nonisolated` on actor types (file-system check only, no actor state).
    nonisolated func localURL(for segmentId: String, in directory: URL) -> URL?

    /// Posts a listening-session event (start/heartbeat/end) to count audio time
    /// toward the user's reading sessions and streak.
    func postAudioSessionEvent(
        event: String,
        bookId: String,
        chapterNumber: Int,
        sessionId: String?,
        listeningSeconds: Double?
    ) async throws
}
