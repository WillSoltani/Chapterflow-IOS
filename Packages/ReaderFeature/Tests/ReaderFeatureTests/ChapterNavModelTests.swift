import Testing
import Foundation
@testable import ReaderFeature
import Models

// MARK: - Test helpers

@MainActor
private func makeManifest(chapterCount: Int = 5) -> BookManifest {
    let chapters = (1...chapterCount).map { n in
        BookManifestChapter(
            chapterId: "ch-\(n)",
            number: n,
            title: "Chapter \(n)",
            readingTimeMinutes: 10,
            chapterKey: nil,
            quizKey: nil
        )
    }
    let cover = Cover(emoji: "📖", color: "#000000")
    return BookManifest(
        bookId: "test-book",
        title: "Test Book",
        author: "Author",
        categories: [],
        tags: [],
        cover: cover,
        variantFamily: .emh,
        status: "published",
        latestVersion: 1,
        currentPublishedVersion: 1,
        updatedAt: "2024-01-01T00:00:00Z",
        chapters: chapters,
        totalReadingTimeMinutes: nil,
        chapterCount: chapterCount
    )
}

@MainActor
private func makeProgress(
    currentChapter: Int = 1,
    unlockedThrough: Int = 3,
    completed: [Int] = [1, 2]
) -> BookProgress {
    BookProgress(
        currentChapterNumber: currentChapter,
        unlockedThroughChapterNumber: unlockedThrough,
        completedChapters: completed,
        bestScoreByChapter: [:],
        preferredVariant: nil,
        progressRev: 1
    )
}

@MainActor
private func makeModel(
    currentChapter: Int = 3,
    unlockedThrough: Int = 3,
    completed: [Int] = [1, 2],
    chapterCount: Int = 5
) -> ChapterNavModel {
    ChapterNavModel(
        manifest: makeManifest(chapterCount: chapterCount),
        progress: makeProgress(
            currentChapter: currentChapter,
            unlockedThrough: unlockedThrough,
            completed: completed
        ),
        currentChapterNumber: currentChapter
    )
}

// MARK: - Item generation

@MainActor
struct ChapterNavItemTests {

    @Test("items are sorted by chapter number")
    func itemsAreSorted() {
        let model = makeModel()
        let numbers = model.items.map { $0.chapter.number }
        #expect(numbers == numbers.sorted())
    }

    @Test("item count matches manifest chapters")
    func itemCountMatchesManifest() {
        let model = makeModel(chapterCount: 7)
        #expect(model.items.count == 7)
    }

    @Test("locked state is SERVER-TRUTH: chapters beyond unlockedThrough are locked")
    func lockedState() {
        // unlockedThrough = 3 → chapters 4 and 5 are locked
        let model = makeModel(unlockedThrough: 3, chapterCount: 5)
        let locked = model.items.filter { $0.isLocked }.map { $0.chapter.number }
        #expect(locked == [4, 5])
    }

    @Test("unlocked state: chapters ≤ unlockedThrough are not locked")
    func unlockedState() {
        let model = makeModel(unlockedThrough: 3, chapterCount: 5)
        let unlocked = model.items.filter { !$0.isLocked }.map { $0.chapter.number }
        #expect(unlocked == [1, 2, 3])
    }

    @Test("completed state matches BookProgress.completedChapters")
    func completedState() {
        let model = makeModel(completed: [1, 2])
        let completed = model.items.filter { $0.isCompleted }.map { $0.chapter.number }
        #expect(completed == [1, 2])
    }

    @Test("isCurrent is true only for the current chapter number")
    func currentChapterMarked() {
        let model = makeModel(currentChapter: 3)
        let current = model.items.filter { $0.isCurrent }.map { $0.chapter.number }
        #expect(current == [3])
    }

    @Test("lockReason is non-nil only for locked chapters")
    func lockReason() {
        let model = makeModel(unlockedThrough: 2, chapterCount: 4)
        for item in model.items {
            if item.isLocked {
                #expect(item.lockReason != nil)
            } else {
                #expect(item.lockReason == nil)
            }
        }
    }
}

// MARK: - Prev / Next

@MainActor
struct ChapterNavPrevNextTests {

    @Test("canGoPrevious is false when currentChapter is 1")
    func cannotGoBackFromChapter1() {
        let model = makeModel(currentChapter: 1, unlockedThrough: 3)
        #expect(!model.canGoPrevious)
    }

    @Test("canGoPrevious is true when currentChapter > 1")
    func canGoBackFromChapter2() {
        let model = makeModel(currentChapter: 2, unlockedThrough: 3)
        #expect(model.canGoPrevious)
    }

    @Test("canGoNext is false when next chapter is locked")
    func cannotGoForwardWhenLocked() {
        // unlockedThrough = 3, currentChapter = 3 → next (4) is locked
        let model = makeModel(currentChapter: 3, unlockedThrough: 3)
        #expect(!model.canGoNext)
    }

    @Test("canGoNext is true when next chapter is unlocked")
    func canGoForwardWhenUnlocked() {
        // unlockedThrough = 4, currentChapter = 3 → next (4) is unlocked
        let model = makeModel(currentChapter: 3, unlockedThrough: 4)
        #expect(model.canGoNext)
    }

    @Test("canGoNext is false when at last chapter")
    func cannotGoForwardAtLastChapter() {
        let model = makeModel(currentChapter: 5, unlockedThrough: 5, chapterCount: 5)
        #expect(!model.canGoNext)
    }

    @Test("goToPreviousChapter fires callback with chapterNumber - 1")
    func previousFiresCallback() {
        let model = makeModel(currentChapter: 3, unlockedThrough: 3)
        var received: Int?
        model.onNavigateToChapter = { received = $0 }
        model.goToPreviousChapter()
        #expect(received == 2)
    }

    @Test("goToPreviousChapter is a no-op at chapter 1")
    func previousNoOpAtChapter1() {
        let model = makeModel(currentChapter: 1, unlockedThrough: 3)
        var called = false
        model.onNavigateToChapter = { _ in called = true }
        model.goToPreviousChapter()
        #expect(!called)
    }

    @Test("goToNextChapter fires callback with chapterNumber + 1")
    func nextFiresCallback() {
        let model = makeModel(currentChapter: 3, unlockedThrough: 4)
        var received: Int?
        model.onNavigateToChapter = { received = $0 }
        model.goToNextChapter()
        #expect(received == 4)
    }

    @Test("goToNextChapter is a no-op when next chapter is locked")
    func nextNoOpWhenLocked() {
        let model = makeModel(currentChapter: 3, unlockedThrough: 3)
        var called = false
        model.onNavigateToChapter = { _ in called = true }
        model.goToNextChapter()
        #expect(!called)
    }
}

// MARK: - ToC navigation

@MainActor
struct ChapterNavNavigateTests {

    @Test("navigate(to:) fires callback and closes ToC for unlocked chapter")
    func navigateUnlocked() {
        let model = makeModel(currentChapter: 1, unlockedThrough: 3)
        model.isToCPresented = true
        var received: Int?
        model.onNavigateToChapter = { received = $0 }
        model.navigate(to: 2)
        #expect(received == 2)
        #expect(!model.isToCPresented)
    }

    @Test("navigate(to:) is a no-op for locked chapters (server-truth gating)")
    func navigateLockedIsNoOp() {
        // chapter 4 is locked (unlockedThrough = 3)
        let model = makeModel(currentChapter: 1, unlockedThrough: 3, chapterCount: 5)
        var called = false
        model.onNavigateToChapter = { _ in called = true }
        model.navigate(to: 4)
        #expect(!called)
    }

    @Test("navigate(to:) is a no-op for a chapter not in the manifest")
    func navigateNonExistentChapter() {
        let model = makeModel(currentChapter: 1, unlockedThrough: 3, chapterCount: 3)
        var called = false
        model.onNavigateToChapter = { _ in called = true }
        model.navigate(to: 99)
        #expect(!called)
    }
}

// MARK: - isLocked / isCompleted helpers

@MainActor
struct ChapterNavLockHelperTests {

    @Test("isLocked returns true for chapters beyond unlockedThroughChapterNumber")
    func isLockedBeyondUnlocked() {
        let model = makeModel(unlockedThrough: 2)
        let ch3 = makeManifest().chapters.first { $0.number == 3 }!
        #expect(model.isLocked(ch3))
    }

    @Test("isLocked returns false for chapters at or below unlockedThroughChapterNumber")
    func isLockedAtUnlocked() {
        let model = makeModel(unlockedThrough: 3)
        let ch3 = makeManifest().chapters.first { $0.number == 3 }!
        #expect(!model.isLocked(ch3))
    }

    @Test("isCompleted returns true for chapters in completedChapters")
    func isCompletedForCompletedChapter() {
        let model = makeModel(completed: [1, 2])
        let ch2 = makeManifest().chapters.first { $0.number == 2 }!
        #expect(model.isCompleted(ch2))
    }

    @Test("isCompleted returns false for chapters not in completedChapters")
    func isCompletedForIncompleteChapter() {
        let model = makeModel(completed: [1])
        let ch3 = makeManifest().chapters.first { $0.number == 3 }!
        #expect(!model.isCompleted(ch3))
    }
}
