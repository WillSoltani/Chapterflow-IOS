import Foundation

/// The full search index returned by `GET /book/search-index`.
///
/// Contains books with their chapter titles so the client can search
/// across all content without hitting per-chapter endpoints. Decoded
/// lossily — one malformed book is dropped while the rest survive.
public struct SearchIndexResponse: Codable, Sendable {
    public let books: [SearchIndexBook]

    private enum CodingKeys: String, CodingKey { case books }

    public init(books: [SearchIndexBook]) {
        self.books = books
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.books = try container.decodeLossy(SearchIndexBook.self, forKey: .books)
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
        bookId = try container.decode(String.self, forKey: .bookId)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        categories = (try? container.decode([String].self, forKey: .categories)) ?? []
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        cover = try? container.decodeIfPresent(Cover.self, forKey: .cover) ?? nil
        chapters = (try? container.decodeLossy(SearchIndexChapter.self, forKey: .chapters)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case bookId, title, author, categories, tags, cover, chapters
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
