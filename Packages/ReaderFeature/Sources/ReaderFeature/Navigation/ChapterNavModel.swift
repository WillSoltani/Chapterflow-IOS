import Foundation
import Observation
import Models

// MARK: - ChapterNavItem

/// A single table-of-contents entry combining manifest chapter data with
/// server-authoritative progress state.
///
/// **Unlock gating is SERVER-TRUTH** — `isLocked` is derived from
/// `BookProgress.unlockedThroughChapterNumber`, never computed client-side.
public struct ChapterNavItem: Sendable, Identifiable {
    public let chapter: BookManifestChapter
    /// True when `chapter.number > progress.unlockedThroughChapterNumber`.
    public let isLocked: Bool
    public let isCompleted: Bool
    public let isCurrent: Bool

    public var id: String { chapter.chapterId }

    /// Human-readable explanation shown below a locked chapter row.
    public var lockReason: String? {
        isLocked ? "Complete earlier chapters to unlock" : nil
    }
}

// MARK: - ChapterNavModel

/// Owns table-of-contents state and previous/next chapter navigation.
///
/// ### Server-truth invariant
/// This model **never writes** unlock or completion state.
/// `isLocked` / `isCompleted` are derived purely from
/// `BookProgress.unlockedThroughChapterNumber` and
/// `BookProgress.completedChapters`.
///
/// Locked chapters are non-navigable: `navigate(to:)` silently ignores them
/// and the view must never allow the user to trigger them.
@Observable
@MainActor
public final class ChapterNavModel {

    // MARK: Server-authoritative data

    public private(set) var manifest: BookManifest
    public private(set) var progress: BookProgress
    public private(set) var currentChapterNumber: Int

    // MARK: Presentation state

    /// Controls ToC sheet (iPhone) or sidebar (iPad).
    public var isToCPresented: Bool = false

    // MARK: Navigation callback

    /// Injected by the host (AppFeature). The host creates a new `ReaderModel`
    /// for the requested chapter number. This model never navigates directly.
    public var onNavigateToChapter: ((Int) -> Void)?

    // MARK: Init

    public init(
        manifest: BookManifest,
        progress: BookProgress,
        currentChapterNumber: Int
    ) {
        self.manifest = manifest
        self.progress = progress
        self.currentChapterNumber = currentChapterNumber
    }

    // MARK: Computed ToC items

    /// All chapters sorted by number with their current nav state.
    public var items: [ChapterNavItem] {
        manifest.chapters
            .sorted { $0.number < $1.number }
            .map { chapter in
                ChapterNavItem(
                    chapter: chapter,
                    isLocked: isLocked(chapter),
                    isCompleted: isCompleted(chapter),
                    isCurrent: chapter.number == currentChapterNumber
                )
            }
    }

    // MARK: Prev / Next availability (SERVER-TRUTH)

    /// Previous chapter is always accessible once started (lower-numbered
    /// chapters are unlocked when higher ones are).
    public var canGoPrevious: Bool {
        currentChapterNumber > 1 && !manifest.chapters.isEmpty
    }

    /// Next chapter is navigable only when unlocked per server progress.
    public var canGoNext: Bool {
        let next = currentChapterNumber + 1
        let exists = manifest.chapters.contains { $0.number == next }
        return exists && next <= progress.unlockedThroughChapterNumber
    }

    // MARK: Navigation actions

    public func goToPreviousChapter() {
        guard canGoPrevious else { return }
        onNavigateToChapter?(currentChapterNumber - 1)
    }

    public func goToNextChapter() {
        guard canGoNext else { return }
        onNavigateToChapter?(currentChapterNumber + 1)
    }

    /// Navigates to an unlocked chapter and dismisses the ToC.
    /// Locked chapters are silently ignored — gating is server-truth.
    public func navigate(to chapterNumber: Int) {
        guard let chapter = manifest.chapters.first(where: { $0.number == chapterNumber }),
              !isLocked(chapter) else { return }
        isToCPresented = false
        onNavigateToChapter?(chapterNumber)
    }

    // MARK: Lock helpers (SERVER-TRUTH — never mutate from here)

    public func isLocked(_ chapter: BookManifestChapter) -> Bool {
        chapter.number > progress.unlockedThroughChapterNumber
    }

    public func isCompleted(_ chapter: BookManifestChapter) -> Bool {
        progress.completedChapters.contains(chapter.number)
    }
}
