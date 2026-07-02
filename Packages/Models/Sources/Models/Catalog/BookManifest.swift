/// Full metadata and table-of-contents for a single book.
///
/// Returned by `GET /book/books/{bookId}`.
public struct BookManifest: Codable, Sendable {
    public let bookId: String
    public let title: String
    public let author: String
    public let categories: [String]
    public let tags: [String]
    public let cover: Cover?
    public let variantFamily: VariantFamily
    public let status: String
    public let latestVersion: Int
    public let currentPublishedVersion: Int?
    public let updatedAt: String
    public let chapters: [BookManifestChapter]

    public let description: String?
    public let shortDescription: String?
    public let totalReadingTimeMinutes: Int?
    public let chapterCount: Int?

    public init(
        bookId: String,
        title: String,
        author: String,
        categories: [String],
        tags: [String],
        cover: Cover?,
        variantFamily: VariantFamily,
        status: String,
        latestVersion: Int,
        currentPublishedVersion: Int?,
        updatedAt: String,
        chapters: [BookManifestChapter],
        description: String? = nil,
        shortDescription: String? = nil,
        totalReadingTimeMinutes: Int? = nil,
        chapterCount: Int? = nil
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.categories = categories
        self.tags = tags
        self.cover = cover
        self.variantFamily = variantFamily
        self.status = status
        self.latestVersion = latestVersion
        self.currentPublishedVersion = currentPublishedVersion
        self.updatedAt = updatedAt
        self.chapters = chapters
        self.description = description
        self.shortDescription = shortDescription
        self.totalReadingTimeMinutes = totalReadingTimeMinutes
        self.chapterCount = chapterCount
    }
}

/// A lightweight chapter entry in the book's table of contents.
///
/// Does not contain content — use `GET /book/books/{bookId}/chapters/{n}` for that.
public struct BookManifestChapter: Codable, Sendable, Identifiable {
    public let chapterId: String
    public let number: Int
    public let title: String
    public let readingTimeMinutes: Int
    public let chapterKey: String?
    public let quizKey: String?

    public var id: String { chapterId }

    public init(
        chapterId: String,
        number: Int,
        title: String,
        readingTimeMinutes: Int,
        chapterKey: String?,
        quizKey: String?
    ) {
        self.chapterId = chapterId
        self.number = number
        self.title = title
        self.readingTimeMinutes = readingTimeMinutes
        self.chapterKey = chapterKey
        self.quizKey = quizKey
    }
}
