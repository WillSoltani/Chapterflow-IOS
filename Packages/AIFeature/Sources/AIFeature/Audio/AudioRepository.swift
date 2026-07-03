import Foundation

/// Data contract for resolving a chapter's streaming audio URL.
///
/// Concrete implementations: ``LiveAudioRepository`` (production) and
/// ``FakeAudioRepository`` (tests and previews).
public protocol AudioRepository: Sendable {
    /// Fetches a signed audio URL for the given chapter.
    ///
    /// - Parameters:
    ///   - bookId: The book the chapter belongs to.
    ///   - chapterNumber: The 1-based chapter number.
    /// - Returns: A `URL` pointing to the chapter's audio stream.
    /// - Throws: `AppError.offline` when offline; other `AppError` cases on failures.
    func chapterAudioURL(bookId: String, chapterNumber: Int) async throws -> URL
}
