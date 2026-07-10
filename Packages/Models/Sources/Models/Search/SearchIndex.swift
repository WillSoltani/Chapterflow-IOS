import Foundation

/// The full search index returned by `GET /book/search-index`.
///
/// Contains books with their chapter titles so the client can search
/// across all content without hitting per-chapter endpoints. Decoded
/// lossily — one malformed book is dropped while the rest survive.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route returns a BARE ARRAY of index entries; caches/fixtures
/// use the canonical `{"books": […]}` envelope. Both decode; encoding stays
/// canonical. See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.
public struct SearchIndexResponse: Codable, Sendable {
    public let books: [SearchIndexBook]

    private enum CodingKeys: String, CodingKey { case books }

    public init(books: [SearchIndexBook]) {
        self.books = books
    }

    public init(from decoder: any Decoder) throws {
        // Deployed shape: a bare top-level array.
        if let bare = try? LossyArray<SearchIndexBook>(from: decoder) {
            self.books = bare.elements
            return
        }
        // Canonical shape: {"books": […]}.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.books = try container.decodeLossy(SearchIndexBook.self, forKey: .books)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(books, forKey: .books)
    }
}

/// A book entry in the search index, including its lightweight chapter list.
///
/// Identical to `BookCatalogItem` in shape but carries `chapters` so the
/// client can match chapter titles to queries. Use tolerant decoding per RF2.
public struct SearchIndexBook: Codable, Sendable, Identifiable {
    public let bookId: String
    public let title: String
    public let author: String
    public let categories: [String]
    public let tags: [String]
    public let cover: Cover?
    public let chapters: [SearchIndexChapter]

    public var id: String { bookId }

    public init(
        bookId: String,
        title: String,
        author: String,
        categories: [String],
        tags: [String],
        cover: Cover?,
        chapters: [SearchIndexChapter]
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.categories = categories
        self.tags = tags
        self.cover = cover
        self.chapters = chapters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Deployed index entries key the id `bookId` (with a composite `id`
        // like "book:slug" alongside) and the title `bookTitle`.
        bookId = try container.decodeRequiredFirst(String.self, keys: [.bookId, .id])
        title = container.decodeFirst(String.self, keys: [.title, .bookTitle]) ?? ""
        author = container.decodeFirst(String.self, keys: [.author]) ?? ""
        categories = (try? container.decode([String].self, forKey: .categories)) ?? []
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        cover = try? container.decodeIfPresent(Cover.self, forKey: .cover) ?? nil
        chapters = (try? container.decodeLossy(SearchIndexChapter.self, forKey: .chapters)) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookId, forKey: .bookId)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(categories, forKey: .categories)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(cover, forKey: .cover)
        try container.encode(chapters, forKey: .chapters)
    }

    private enum CodingKeys: String, CodingKey {
        case bookId, id, bookTitle
        case title, author, categories, tags, cover, chapters
    }
}

/// A lightweight chapter entry in the search index (title only, no content).
public struct SearchIndexChapter: Codable, Sendable, Identifiable {
    public let chapterId: String
    public let number: Int
    public let title: String

    public var id: String { chapterId }

    public init(chapterId: String, number: Int, title: String) {
        self.chapterId = chapterId
        self.number = number
        self.title = title
    }
}
