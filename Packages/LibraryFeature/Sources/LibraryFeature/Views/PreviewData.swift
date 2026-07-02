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

    // MARK: - Repositories

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
}
#endif
