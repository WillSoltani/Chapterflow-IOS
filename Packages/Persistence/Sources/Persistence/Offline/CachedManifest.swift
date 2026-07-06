import Foundation
import SwiftData
import Models

/// A cached ``BookManifest`` (table of contents + metadata) for a single book.
@Model
public final class CachedManifest {
    /// Composite unique key: "userId:bookId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    /// JSON-encoded BookManifest.
    public var dataJSON: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        dataJSON: String,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.dataJSON = dataJSON
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedManifest {
    public static func makeRowId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }

    public static func from(_ domain: BookManifest, userId: String) throws -> CachedManifest {
        let data = try JSONEncoder().encode(domain)
        return CachedManifest(
            rowId: makeRowId(userId: userId, bookId: domain.bookId),
            userId: userId,
            bookId: domain.bookId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    public func toDomain() throws -> BookManifest {
        try JSONDecoder.chapterFlow.decode(BookManifest.self, from: Data(dataJSON.utf8))
    }
}
