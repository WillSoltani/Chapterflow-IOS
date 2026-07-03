import Foundation
import Models
import Persistence

// MARK: - Protocol

/// Data boundary for all reader I/O: content loading, cursor tracking, session heartbeats,
/// and local reading-position persistence.
///
/// Repositories are protocols so tests can inject in-memory fakes without the network.
public protocol ReaderRepository: Sendable {
    /// Fetches a chapter and the user's current progress from the server.
    func getChapter(bookId: String, n: Int, mode: String?) async throws -> ChapterResponse

    /// Advances the server cursor to `chapterId` (PATCH is forward-only;
    /// the caller is responsible for never sending a lower chapter number).
    func patchBookCursor(bookId: String, chapterId: String) async throws

    /// Starts a reading session and returns the server-assigned sessionId (nil on failure).
    /// Fire-and-forget: failures are logged and never surface to the reader UI.
    func startReadingSession(bookId: String, chapterId: String) async -> String?

    /// Posts a heartbeat for an active reading session (fire-and-forget;
    /// failures are swallowed so they never interrupt reading).
    func postReadingHeartbeat(bookId: String, chapterId: String, sessionId: String?) async

    /// Ends a reading session. Fire-and-forget best-effort call.
    func endReadingSession(bookId: String, chapterId: String, sessionId: String?) async

    /// Fetches the book-level state including per-chapter applicationStates.
    /// Used to drive the two-axis completion display (knowledge + application).
    func getBookState(bookId: String) async throws -> BookStateResponse

    /// Persists the reading position (block index) locally so it can be
    /// restored on the next open — even after changing font or theme.
    func saveScrollPosition(bookId: String, chapterNumber: Int, blockIndex: Int)

    /// Returns the previously saved block index for a chapter, or `nil` if none.
    func loadScrollPosition(bookId: String, chapterNumber: Int) -> Int?
}
