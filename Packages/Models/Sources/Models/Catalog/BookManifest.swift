/// Full metadata and table-of-contents for a single book.
///
/// Returned by `GET /book/books/{bookId}`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route wraps the payload as `{"book": {…}}` and emits the web
/// catalog shape (`id`, `publishedVersion`, `icon`/`coverImage`, `synopsis`,
/// `estimatedMinutes`, chapters with `minutes`), while caches/fixtures use the
/// canonical bare shape. This model decodes BOTH (wrapped or bare, either key
/// spelling) and always encodes the canonical bare shape. Only `bookId` is
/// required. See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.
public struct BookManifest: Codable, Sendable {
    public let bookId: String
    public let title: String
    public let author: String
    public let categories: [String]
    public let tags: [String]
    public let cover: Cover?
    /// Remote cover-art URL when the server provides one (`coverImage`).
    public let coverImageURL: String?
    public let variantFamily: VariantFamily
    /// Logic-dead on this client; absent on the wire.
    public let status: String?
    /// Logic-dead on this client; the wire sends `publishedVersion`.
    public let latestVersion: Int?
    public let currentPublishedVersion: Int?
    public let updatedAt: String?
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
        status: String? = nil,
        latestVersion: Int? = nil,
        currentPublishedVersion: Int? = nil,
        updatedAt: String? = nil,
        chapters: [BookManifestChapter],
        description: String? = nil,
        shortDescription: String? = nil,
        totalReadingTimeMinutes: Int? = nil,
        chapterCount: Int? = nil,
        coverImageURL: String? = nil
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.categories = categories
        self.tags = tags
        self.cover = cover
        self.coverImageURL = coverImageURL
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

    /// Canonical names first; deployed web-shape alternates after.
    private enum WireKeys: String, CodingKey {
        case book
        case bookId, id
        case title, author, categories, tags, cover, variantFamily, status
        case latestVersion, publishedVersion, currentPublishedVersion, updatedAt
        case chapters
        case description, synopsis, shortDescription
        case totalReadingTimeMinutes, estimatedMinutes, chapterCount
        case coverImageURL, coverImage, icon
    }

    public init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: WireKeys.self)
        // The deployed route nests the payload under `book`; caches are bare.
        let c: KeyedDecodingContainer<WireKeys>
        if root.contains(.book),
           let nested = try? root.nestedContainer(keyedBy: WireKeys.self, forKey: .book) {
            c = nested
        } else {
            c = root
        }

        bookId = try c.decodeRequiredFirst(String.self, keys: [.bookId, .id])
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        author = c.decodeFirst(String.self, keys: [.author]) ?? ""
        categories = c.decodeFirst([String].self, keys: [.categories]) ?? []
        tags = c.decodeFirst([String].self, keys: [.tags]) ?? []
        if let coverObject = c.decodeFirst(Cover.self, keys: [.cover]) {
            cover = coverObject
        } else if let icon = c.decodeFirst(String.self, keys: [.icon]) {
            cover = Cover(emoji: icon, color: nil)
        } else {
            cover = nil
        }
        coverImageURL = c.decodeFirst(String.self, keys: [.coverImageURL, .coverImage])
        variantFamily = c.decodeFirst(VariantFamily.self, keys: [.variantFamily]) ?? .unknown("")
        status = c.decodeFirst(String.self, keys: [.status])
        latestVersion = c.decodeFirst(Int.self, keys: [.latestVersion, .publishedVersion])
        currentPublishedVersion = c.decodeFirst(
            Int.self, keys: [.currentPublishedVersion, .publishedVersion])
        updatedAt = c.decodeFirst(String.self, keys: [.updatedAt])
        chapters = (try? c.decodeLossy(BookManifestChapter.self, forKey: .chapters)) ?? []
        description = c.decodeFirst(String.self, keys: [.description, .synopsis])
        shortDescription = c.decodeFirst(String.self, keys: [.shortDescription])
        totalReadingTimeMinutes = c.decodeFirst(
            Int.self, keys: [.totalReadingTimeMinutes, .estimatedMinutes])
        chapterCount = c.decodeFirst(Int.self, keys: [.chapterCount])
    }

    /// Always encodes the canonical BARE shape (no `book` wrapper).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(bookId, forKey: .bookId)
        try c.encode(title, forKey: .title)
        try c.encode(author, forKey: .author)
        try c.encode(categories, forKey: .categories)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(coverImageURL, forKey: .coverImageURL)
        try c.encode(variantFamily, forKey: .variantFamily)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(latestVersion, forKey: .latestVersion)
        try c.encodeIfPresent(currentPublishedVersion, forKey: .currentPublishedVersion)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encode(chapters, forKey: .chapters)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try c.encodeIfPresent(totalReadingTimeMinutes, forKey: .totalReadingTimeMinutes)
        try c.encodeIfPresent(chapterCount, forKey: .chapterCount)
    }
}

/// A lightweight chapter entry in the book's table of contents.
///
/// Does not contain content — use `GET /book/books/{bookId}/chapters/{n}` for that.
/// Tolerates the deployed web shape (`id`, `minutes`, `code`) alongside the
/// canonical one (`chapterId`, `readingTimeMinutes`).
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

    private enum WireKeys: String, CodingKey {
        case chapterId, id
        case number, title
        case readingTimeMinutes, minutes
        case chapterKey, quizKey
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        chapterId = try c.decodeRequiredFirst(String.self, keys: [.chapterId, .id])
        number = c.decodeFirst(Int.self, keys: [.number]) ?? 0
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        readingTimeMinutes = c.decodeFirst(Int.self, keys: [.readingTimeMinutes, .minutes]) ?? 0
        chapterKey = c.decodeFirst(String.self, keys: [.chapterKey])
        quizKey = c.decodeFirst(String.self, keys: [.quizKey])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(chapterId, forKey: .chapterId)
        try c.encode(number, forKey: .number)
        try c.encode(title, forKey: .title)
        try c.encode(readingTimeMinutes, forKey: .readingTimeMinutes)
        try c.encodeIfPresent(chapterKey, forKey: .chapterKey)
        try c.encodeIfPresent(quizKey, forKey: .quizKey)
    }
}
