import Foundation
import Models
import Networking
import CoreKit

// MARK: - NotebookEntry preview fixtures

extension NotebookEntry {
    static let previewEntries: [NotebookEntry] = [
        NotebookEntry(
            entryId: "entry-1",
            bookId: "atomic-habits",
            chapterId: "ch-3",
            type: .note,
            content: "The 1% improvement rule is deceptively powerful — small daily changes compound over time to create massive results.",
            quote: nil,
            createdAt: "2026-07-01T10:00:00Z",
            updatedAt: "2026-07-01T10:00:00Z",
            bookTitle: "Atomic Habits",
            chapterTitle: "Make It Obvious",
            chapterNumber: 3,
            tags: ["habits", "improvement"]
        ),
        NotebookEntry(
            entryId: "entry-2",
            bookId: "atomic-habits",
            chapterId: "ch-5",
            type: .reflection,
            content: "I notice I reach for my phone whenever I sit at my desk. This is a cue I can redesign.",
            quote: nil,
            createdAt: "2026-07-02T08:30:00Z",
            updatedAt: "2026-07-02T08:30:00Z",
            bookTitle: "Atomic Habits",
            chapterTitle: "The Best Way to Start a New Habit",
            chapterNumber: 5,
            tags: ["personal", "reflection"]
        ),
        NotebookEntry(
            entryId: "entry-3",
            bookId: "deep-work",
            chapterId: "ch-1",
            type: .highlight,
            content: nil,
            quote: "Deep work is the ability to focus without distraction on a cognitively demanding task.",
            createdAt: "2026-06-28T14:00:00Z",
            updatedAt: "2026-06-28T14:00:00Z",
            bookTitle: "Deep Work",
            chapterTitle: "Deep Work Is Valuable",
            chapterNumber: 1,
            tags: ["focus", "productivity"]
        ),
        NotebookEntry(
            entryId: "entry-4",
            bookId: "atomic-habits",
            chapterId: "ch-7",
            type: .bookmark,
            content: nil,
            quote: "You do not rise to the level of your goals. You fall to the level of your systems.",
            createdAt: "2026-07-02T16:00:00Z",
            updatedAt: "2026-07-02T16:00:00Z",
            bookTitle: "Atomic Habits",
            chapterTitle: "The Role of Identity",
            chapterNumber: 7,
            tags: nil
        ),
        NotebookEntry(
            entryId: "entry-5",
            bookId: "deep-work",
            chapterId: "ch-2",
            type: .commitment,
            content: "I will block 9am–12pm every weekday for deep work sessions, starting Monday.",
            quote: nil,
            createdAt: "2026-06-29T09:00:00Z",
            updatedAt: "2026-06-29T09:00:00Z",
            bookTitle: "Deep Work",
            chapterTitle: "Deep Work Is Rare",
            chapterNumber: 2,
            tags: ["commitment", "focus"]
        ),
    ]
}

// MARK: - NotebookModel preview

extension NotebookModel {
    static var preview: NotebookModel {
        let repo = NotebookRepository.preview
        let model = NotebookModel(repository: repo)
        model.seedForPreview(entries: NotebookEntry.previewEntries, state: .loaded)
        return model
    }

    static var previewLoading: NotebookModel {
        // Default initialState is .loading — no seeding needed
        return NotebookModel(repository: NotebookRepository.preview)
    }
}

// MARK: - SavedBooksModel preview

extension SavedBooksModel {
    static var preview: SavedBooksModel {
        let repo = NotebookRepository.preview
        let catalog = BookCatalogItem.previewCatalog
        let model = SavedBooksModel(repository: repo) { catalog }
        model.seedForPreview(
            savedBookIds: ["atomic-habits", "deep-work"],
            catalog: catalog,
            state: .loaded
        )
        return model
    }
}

// MARK: - BookCatalogItem preview fixtures (local to EngagementFeature)

extension BookCatalogItem {
    static let previewCatalog: [BookCatalogItem] = [
        BookCatalogItem(
            bookId: "atomic-habits",
            title: "Atomic Habits",
            author: "James Clear",
            categories: ["Self-Help"],
            tags: ["habits", "productivity"],
            cover: Cover(emoji: "⚡️", color: "1A3B6E"),
            variantFamily: .emh,
            status: "published",
            latestVersion: 1,
            currentPublishedVersion: 1,
            updatedAt: "2024-01-01T00:00:00Z"
        ),
        BookCatalogItem(
            bookId: "deep-work",
            title: "Deep Work",
            author: "Cal Newport",
            categories: ["Productivity"],
            tags: ["focus", "work"],
            cover: Cover(emoji: "🎯", color: "2D5A27"),
            variantFamily: .emh,
            status: "published",
            latestVersion: 1,
            currentPublishedVersion: 1,
            updatedAt: "2024-01-01T00:00:00Z"
        ),
        BookCatalogItem(
            bookId: "thinking-fast-and-slow",
            title: "Thinking, Fast and Slow",
            author: "Daniel Kahneman",
            categories: ["Psychology"],
            tags: ["decision-making", "psychology"],
            cover: Cover(emoji: "🧠", color: "5C2D8F"),
            variantFamily: .pbc,
            status: "published",
            latestVersion: 1,
            currentPublishedVersion: 1,
            updatedAt: "2024-01-01T00:00:00Z"
        ),
    ]
}

// MARK: - NotebookRepository preview

extension NotebookRepository {
    static var preview: NotebookRepository {
        let entries = NotebookEntry.previewEntries
        let savedIds = ["atomic-habits", "deep-work"]
        let client = NotebookPreviewAPIClient(entries: entries, savedIds: savedIds)
        return NotebookRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - Encoding wrappers (file-level to avoid nested-in-generic errors)

private struct PreviewEntriesWrapper: Encodable {
    let entries: [NotebookEntry]
}

private struct PreviewSavedWrapper: Encodable {
    let savedBookIds: [String]
}

// MARK: - NotebookPreviewAPIClient

private final class NotebookPreviewAPIClient: APIClientProtocol, @unchecked Sendable {
    private let entries: [NotebookEntry]
    private let savedIds: [String]

    init(entries: [NotebookEntry], savedIds: [String]) {
        self.entries = entries
        self.savedIds = savedIds
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data: Data
        switch endpoint.path {
        case "/book/me/notebook":
            data = try JSONCoding.encoder.encode(PreviewEntriesWrapper(entries: entries))
        case "/book/me/saved":
            data = try JSONCoding.encoder.encode(PreviewSavedWrapper(savedBookIds: savedIds))
        default:
            throw AppError.notFound
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}
