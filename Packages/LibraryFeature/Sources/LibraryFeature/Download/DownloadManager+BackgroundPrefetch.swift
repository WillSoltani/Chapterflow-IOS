import Foundation
import Persistence
import os

// MARK: - Background prefetch & resume

extension DownloadManager {

    // MARK: - Resume interrupted downloads

    /// Resumes any downloads that were interrupted (status `.downloading`).
    ///
    /// Called from a BGProcessing task. Processes one book at a time to stay
    /// within the limited CPU and network budget of background execution.
    /// Respects task cancellation between books.
    public func resumeInterruptedDownloads(userId: String) async {
        let bg = BackgroundStore(modelContainer: container)
        let bookIds = (try? await bg.interruptedDownloadBookIds(userId: userId)) ?? []
        guard !bookIds.isEmpty else { return }

        logger.info("BGSync: resuming \(bookIds.count) interrupted download(s)")
        for bookId in bookIds {
            if Task.isCancelled { break }
            for await event in downloadBook(bookId: bookId, userId: userId) {
                if Task.isCancelled { break }
                if case .complete = event.phase { break }
                if case .failed = event.phase { break }
            }
        }
    }

    // MARK: - Prefetch next chapters

    /// Prefetches the next unread chapter for each in-progress book.
    ///
    /// Called from a BGProcessing task. Reads `CachedBookState` to determine
    /// which chapter the user is currently on, then downloads the following chapter
    /// if it isn't already cached. Skips books whose manifest isn't cached locally
    /// (the user hasn't opened them offline yet).
    ///
    /// Respects task cancellation between books.
    public func prefetchNextChapters(userId: String) async {
        let bg = BackgroundStore(modelContainer: container)
        let inProgress = (try? await bg.inProgressBookStates(userId: userId)) ?? []
        guard !inProgress.isEmpty else { return }

        logger.info("BGSync: prefetching next chapters for \(inProgress.count) book(s)")

        for entry in inProgress {
            if Task.isCancelled { break }
            await prefetchNextChapter(
                bookId: entry.bookId,
                currentChapterId: entry.currentChapterId,
                userId: userId,
                bg: bg
            )
        }
    }

    // MARK: - Private helpers

    private func prefetchNextChapter(
        bookId: String,
        currentChapterId: String,
        userId: String,
        bg: BackgroundStore
    ) async {
        // Need the manifest to map chapterId → number and find the next one.
        guard let manifest = try? await bg.cachedManifest(bookId: bookId, userId: userId),
              let currentIndex = manifest.chapters.firstIndex(where: { $0.chapterId == currentChapterId }),
              currentIndex + 1 < manifest.chapters.count else { return }

        let nextChapter = manifest.chapters[currentIndex + 1]

        // Skip if already cached.
        if (try? await bg.isChapterCached(
            bookId: bookId,
            chapterNumber: nextChapter.number,
            userId: userId
        )) == true { return }

        do {
            try await downloadChapter(
                bookId: bookId,
                chapterNumber: nextChapter.number,
                userId: userId,
                bg: bg
            )
            logger.info("BGSync: prefetched ch\(nextChapter.number) of \(bookId)")
        } catch {
            logger.warning("BGSync: prefetch failed for \(bookId) ch\(nextChapter.number): \(error)")
        }
    }
}
