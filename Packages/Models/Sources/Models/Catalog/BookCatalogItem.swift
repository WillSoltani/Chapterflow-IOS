/// A summary entry in the public book catalog.
///
/// Returned by `GET /book/books`.
public struct BookCatalogItem: Codable, Sendable, Identifiable, Equatable {
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

    public var id: String { bookId }

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
        updatedAt: String
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
    }
}

/// The visual cover for a book — an emoji with a gradient background color.
///
/// No image downloads needed; the cover is rendered entirely client-side.
public struct Cover: Codable, Sendable, Equatable {
    public let emoji: String?
    public let color: String?

    public init(emoji: String?, color: String?) {
        self.emoji = emoji
        self.color = color
    }
}
