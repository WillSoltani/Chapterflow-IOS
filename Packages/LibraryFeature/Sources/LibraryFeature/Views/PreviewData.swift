/// Inline sample data for SwiftUI `#Preview` blocks.
///
/// Mirrors the JSON fixtures in the Fixtures package without importing it,
/// keeping the production binary free of test-only resources.
#if DEBUG
import Models

enum PreviewData {

    // MARK: - Books

    static let atomicHabits = BookCatalogItem(
        bookId: "b-atomic-habits",
        title: "Atomic Habits",
        author: "James Clear",
        categories: ["Productivity", "Psychology"],
        tags: ["habits", "behavior-change", "systems"],
        cover: Cover(emoji: "⚛️", color: "#2D6A4F"),
        variantFamily: .emh,
        status: "published",
        latestVersion: 3,
        currentPublishedVersion: 3,
        updatedAt: "2024-01-15T10:00:00.000Z"
    )

    static let deepWork = BookCatalogItem(
        bookId: "b-deep-work",
        title: "Deep Work",
        author: "Cal Newport",
        categories: ["Productivity", "Focus"],
        tags: ["focus", "deep-work", "distraction-free"],
        cover: Cover(emoji: "🎯", color: "#1B4332"),
        variantFamily: .pbc,
        status: "published",
        latestVersion: 2,
        currentPublishedVersion: 2,
        updatedAt: "2024-02-01T09:00:00.000Z"
    )

    static let thinkingFastAndSlow = BookCatalogItem(
        bookId: "b-thinking-fast-slow",
        title: "Thinking, Fast and Slow",
        author: "Daniel Kahneman",
        categories: ["Psychology", "Cognitive Science"],
        tags: ["cognitive-bias", "decision-making"],
        cover: Cover(emoji: "🧠", color: "#1A237E"),
        variantFamily: .emh,
        status: "published",
        latestVersion: 1,
        currentPublishedVersion: 1,
        updatedAt: "2024-01-20T12:00:00.000Z"
    )

    static let books: [BookCatalogItem] = [atomicHabits, deepWork, thinkingFastAndSlow]

    // MARK: - Progress

    static let atomicHabitsProgress = ProgressOverviewItem(
        bookId: "b-atomic-habits",
        currentChapterNumber: 2,
        totalChapters: 5,
        completedChapterCount: 1,
        lastReadAt: "2024-01-16T09:00:00.000Z"
    )

    static let deepWorkProgress = ProgressOverviewItem(
        bookId: "b-deep-work",
        currentChapterNumber: 1,
        totalChapters: 5,
        completedChapterCount: 0,
        lastReadAt: "2024-01-10T14:30:00.000Z"
    )

    static let progressOverview = ProgressOverviewResponse(
        progress: [atomicHabitsProgress, deepWorkProgress]
    )

    // MARK: - Saved

    static let savedBookIds: [String] = ["b-deep-work", "b-thinking-fast-slow"]

    // MARK: - Book manifest

    static let atomicHabitsChapters: [BookManifestChapter] = [
        BookManifestChapter(chapterId: "ch-ah-1", number: 1,
                            title: "The Surprising Power of Atomic Habits",
                            readingTimeMinutes: 12, chapterKey: nil, quizKey: nil),
        BookManifestChapter(chapterId: "ch-ah-2", number: 2,
                            title: "How Your Habits Shape Your Identity",
                            readingTimeMinutes: 14, chapterKey: nil, quizKey: nil),
        BookManifestChapter(chapterId: "ch-ah-3", number: 3,
                            title: "How to Build Better Habits in 4 Simple Steps",
                            readingTimeMinutes: 18, chapterKey: nil, quizKey: nil),
        BookManifestChapter(chapterId: "ch-ah-4", number: 4,
                            title: "The Man Who Didn't Look Right",
                            readingTimeMinutes: 10, chapterKey: nil, quizKey: nil),
        BookManifestChapter(chapterId: "ch-ah-5", number: 5,
                            title: "The Best Way to Start a New Habit",
                            readingTimeMinutes: 16, chapterKey: nil, quizKey: nil),
    ]

    static let atomicHabitsManifest = BookManifest(
        bookId: "b-atomic-habits",
        title: "Atomic Habits",
        author: "James Clear",
        categories: ["Productivity", "Psychology"],
        tags: ["habits", "behavior-change", "systems"],
        cover: Cover(emoji: "⚛️", color: "#2D6A4F"),
        variantFamily: .emh,
        status: "published",
        latestVersion: 3,
        currentPublishedVersion: 3,
        updatedAt: "2024-01-15T10:00:00.000Z",
        chapters: atomicHabitsChapters,
        description: "Tiny changes, remarkable results.",
        shortDescription: "Build good habits through small improvements.",
        totalReadingTimeMinutes: 70,
        chapterCount: 5
    )

    // MARK: - Book states

    /// In-progress: ch.1 completed (score 100), ch.2 unlocked and current.
    static let atomicHabitsState = BookStateResponse(
        state: BookUserBookState(
            currentChapterId: "ch-ah-2",
            completedChapterIds: ["ch-ah-1"],
            unlockedChapterIds: ["ch-ah-1", "ch-ah-2"],
            chapterScores: ["ch-ah-1": 100],
            chapterCompletedAt: ["ch-ah-1": "2024-01-15T14:30:00Z"],
            lastReadChapterId: "ch-ah-2",
            lastOpenedAt: "2024-01-16T09:00:00Z"
        ),
        applicationStates: ["ch-ah-1": .applied, "ch-ah-2": .committed]
    )

    /// Completed: all 5 chapters done.
    static let atomicHabitsCompletedState = BookStateResponse(
        state: BookUserBookState(
            currentChapterId: "ch-ah-5",
            completedChapterIds: ["ch-ah-1", "ch-ah-2", "ch-ah-3", "ch-ah-4", "ch-ah-5"],
            unlockedChapterIds: ["ch-ah-1", "ch-ah-2", "ch-ah-3", "ch-ah-4", "ch-ah-5"],
            chapterScores: [
                "ch-ah-1": 100, "ch-ah-2": 90, "ch-ah-3": 85,
                "ch-ah-4": 100, "ch-ah-5": 95,
            ],
            chapterCompletedAt: [
                "ch-ah-1": "2024-01-15T14:30:00Z",
                "ch-ah-5": "2024-01-20T10:00:00Z",
            ],
            lastReadChapterId: "ch-ah-5",
            lastOpenedAt: "2024-01-20T10:00:00Z"
        ),
        applicationStates: [
            "ch-ah-1": .applied, "ch-ah-2": .applied,
            "ch-ah-3": .committed, "ch-ah-4": .committed, "ch-ah-5": .none,
        ]
    )

    // MARK: - Entitlements

    static let freeLockedEntitlement = EntitlementResponse(
        entitlement: Entitlement(
            plan: .free, proStatus: nil, proSource: nil,
            freeBookSlots: 1, unlockedBookIds: [],
            unlockedBooksCount: 0, remainingFreeStarts: 0,
            currentPeriodEnd: nil, cancelAtPeriodEnd: nil,
            licenseKey: nil, licenseExpiresAt: nil
        ),
        paywall: nil
    )

    static let proEntitlement = EntitlementResponse(
        entitlement: Entitlement(
            plan: .pro, proStatus: "active", proSource: "apple",
            freeBookSlots: 1, unlockedBookIds: ["b-atomic-habits"],
            unlockedBooksCount: 1, remainingFreeStarts: 0,
            currentPeriodEnd: "2025-01-01T00:00:00Z", cancelAtPeriodEnd: false,
            licenseKey: nil, licenseExpiresAt: nil
        ),
        paywall: nil
    )

    // MARK: - LibraryRepository stubs

    static var loadedRepo: FakeLibraryRepository {
        FakeLibraryRepository(
            catalog: books,
            progress: progressOverview,
            savedBookIds: savedBookIds
        )
    }

    static var emptyRepo: FakeLibraryRepository {
        FakeLibraryRepository()
    }

    static var errorRepo: FakeLibraryRepository {
        FakeLibraryRepository(error: .offline)
    }

    // MARK: - BookDetailRepository stubs

    /// Free user, no free slots, book not started → paywall gate.
    static var bookDetailFreeLocked: FakeBookDetailRepository {
        FakeBookDetailRepository(
            manifest: atomicHabitsManifest,
            state: nil,
            stateError: .notFound,
            entitlement: freeLockedEntitlement
        )
    }

    /// Book in-progress (ch.1 done, ch.2 current).
    static var bookDetailInProgress: FakeBookDetailRepository {
        FakeBookDetailRepository(
            manifest: atomicHabitsManifest,
            state: atomicHabitsState,
            entitlement: proEntitlement
        )
    }

    /// Book fully completed.
    static var bookDetailCompleted: FakeBookDetailRepository {
        FakeBookDetailRepository(
            manifest: atomicHabitsManifest,
            state: atomicHabitsCompletedState,
            entitlement: proEntitlement
        )
    }
}
#endif
