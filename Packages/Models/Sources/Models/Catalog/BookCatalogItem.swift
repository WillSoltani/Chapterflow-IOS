/// A summary entry in the public book catalog.
///
/// Returned by `GET /book/books`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed catalog serializer emits a web-UI shape (`id`,
/// `publishedVersion`, `icon`/`coverImage`, no `status`/`updatedAt`), while
/// local caches/fixtures use the canonical documented shape (`bookId`,
/// `latestVersion`, `cover`, …). This model decodes BOTH and always encodes
/// the canonical shape. Only `bookId` is truly required; everything else is
/// optional or defaulted so a partial response can never fail the whole
/// catalog. See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.
public struct BookCatalogItem: Codable, Sendable, Identifiable, Equatable {
    public let bookId: String
    public let title: String
    public let author: String
    public let categories: [String]
    public let tags: [String]
    public let cover: Cover?
    /// Remote cover-art URL when the server provides one (web catalog shape:
    /// `coverImage`). Not yet rendered by `CoverView`; preserved for the UI.
    public let coverImageURL: String?
    public let variantFamily: VariantFamily
    /// Logic-dead on this client (display/versioning only); absent on the wire.
    public let status: String?
    /// Logic-dead on this client; the wire sends `publishedVersion` instead.
    public let latestVersion: Int?
    public let currentPublishedVersion: Int?
    /// Cosmetic — sorts the "New & Updated" shelf; absent on the wire today.
    public let updatedAt: String?
    /// Chapter count from the web catalog shape; used to derive progress
    /// fractions when the progress endpoint omits totals.
    public let chapterCount: Int?

    public var id: String { bookId }

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
        coverImageURL: String? = nil,
        chapterCount: Int? = nil
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
        self.chapterCount = chapterCount
    }

    /// Canonical names first; deployed web-shape alternates after.
    private enum WireKeys: String, CodingKey {
        case bookId, id
        case title, author, categories, tags, cover, variantFamily, status
        case latestVersion, publishedVersion, currentPublishedVersion, updatedAt
        case coverImageURL, coverImage, icon, chapterCount
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        bookId = try c.decodeRequiredFirst(String.self, keys: [.bookId, .id])
        title = c.decodeFirst(String.self, keys: [.title]) ?? ""
        author = c.decodeFirst(String.self, keys: [.author]) ?? ""
        categories = c.decodeFirst([String].self, keys: [.categories]) ?? []
        tags = c.decodeFirst([String].self, keys: [.tags]) ?? []
        // Canonical cover object, else synthesize from the web shape's emoji icon.
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
        chapterCount = c.decodeFirst(Int.self, keys: [.chapterCount])
    }

    /// Always encodes the canonical shape (caches must stay stable even
    /// though the wire uses web-UI names).
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
        try c.encodeIfPresent(chapterCount, forKey: .chapterCount)
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
