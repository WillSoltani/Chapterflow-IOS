import Foundation
import SwiftData
import Models
import Persistence

// MARK: - BackgroundStore extensions for background prefetch & resume

extension BackgroundStore {

    // MARK: - Interrupted download resume

    /// Returns the bookIds of all downloads stuck in `.downloading` status.
    ///
    /// These are downloads that were interrupted mid-flight (e.g. app terminated)
    /// and need to be resumed.
    func interruptedDownloadBookIds(userId: String) throws -> [String] {
        let uid = userId
        let desc = FetchDescriptor<CachedBookDownload>(
            predicate: #Predicate { $0.userId == uid && $0.statusRaw == "downloading" }
        )
        return try modelContext.fetch(desc).map(\.bookId)
    }

    // MARK: - In-progress book states

    /// Returns `(bookId, currentChapterId)` pairs for all books with an active
    /// reading position, used to prefetch the next chapter in the background.
    func inProgressBookStates(userId: String) throws -> [(bookId: String, currentChapterId: String)] {
        let uid = userId
        let desc = FetchDescriptor<CachedBookState>(
            predicate: #Predicate { $0.userId == uid }
        )
        let states = try modelContext.fetch(desc)
        return states.compactMap { cached in
            guard let response = try? JSONDecoder.chapterFlow.decode(
                BookStateResponse.self,
                from: Data(cached.dataJSON.utf8)
            ),
            let chapterId = response.state.currentChapterId,
            !chapterId.isEmpty else { return nil }
            return (bookId: cached.bookId, currentChapterId: chapterId)
        }
    }

    // MARK: - Manifest lookup

    /// Decodes and returns the cached manifest for a book, or `nil` if not cached.
    func cachedManifest(bookId: String, userId: String) throws -> BookManifest? {
        let rowId = CachedManifest.makeRowId(userId: userId, bookId: bookId)
        let desc = FetchDescriptor<CachedManifest>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        guard let cached = try modelContext.fetch(desc).first else { return nil }
        return try JSONDecoder.chapterFlow.decode(
            BookManifest.self,
            from: Data(cached.dataJSON.utf8)
        )
    }

    // MARK: - Chapter cache check

    /// Returns `true` when the chapter content has already been stored locally.
    func isChapterCached(bookId: String, chapterNumber: Int, userId: String) throws -> Bool {
        let rowId = CachedChapter.makeRowId(userId: userId, bookId: bookId, number: chapterNumber)
        let desc = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        return try !modelContext.fetch(desc).isEmpty
    }
}
