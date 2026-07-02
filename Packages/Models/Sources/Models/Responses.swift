/// Top-level response wrappers matching the API's success envelope shapes.
/// Success bodies are raw JSON objects, not nested under a generic wrapper.

/// Decodes the `books` array lossily — one malformed book is dropped and
/// logged while the rest of the catalog survives.
public struct CatalogResponse: Codable, Sendable {
    public let books: [BookCatalogItem]

    private enum CodingKeys: String, CodingKey { case books }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.books = try container.decodeLossy(BookCatalogItem.self, forKey: .books)
    }
}

// MARK: - Library

/// Per-book reading progress summary for the Home "Continue Reading" rail.
/// Returned by `GET /book/me/progress`.
public struct ProgressOverviewItem: Codable, Sendable, Identifiable {
    public let bookId: String
    public let currentChapterNumber: Int
    public let totalChapters: Int
    public let completedChapterCount: Int
    /// ISO-8601 timestamp of the user's last reading session for this book.
    public let lastReadAt: String?

    public var id: String { bookId }

    /// 0…1 fraction of chapters completed.
    public var completionFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(completedChapterCount) / Double(totalChapters)
    }

    public init(
        bookId: String,
        currentChapterNumber: Int,
        totalChapters: Int,
        completedChapterCount: Int,
        lastReadAt: String?
    ) {
        self.bookId = bookId
        self.currentChapterNumber = currentChapterNumber
        self.totalChapters = totalChapters
        self.completedChapterCount = completedChapterCount
        self.lastReadAt = lastReadAt
    }
}

public struct ProgressOverviewResponse: Codable, Sendable {
    public let progress: [ProgressOverviewItem]

    public init(progress: [ProgressOverviewItem]) {
        self.progress = progress
    }
}

/// Saved (bookmarked) book IDs for the current user.
/// Returned by `GET /book/me/saved` and `POST /book/me/saved`.
public struct SavedBooksResponse: Codable, Sendable {
    public let savedBookIds: [String]

    public init(savedBookIds: [String]) {
        self.savedBookIds = savedBookIds
    }
}

public struct ChapterResponse: Codable, Sendable {
    public let chapter: Chapter
    public let progress: BookProgress
}

public struct QuizResponse: Codable, Sendable {
    public let quiz: QuizClientSession
    public let progress: BookProgress

    public init(quiz: QuizClientSession, progress: BookProgress) {
        self.quiz = quiz
        self.progress = progress
    }
}

public struct EntitlementResponse: Codable, Sendable {
    public let entitlement: Entitlement
    public let paywall: Paywall?
}

public struct BookStateResponseEnvelope: Codable, Sendable {
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?
}
