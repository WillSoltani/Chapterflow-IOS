import Foundation
import SwiftData
import Models

/// A cached snapshot of a ``BookCatalogItem``, partitioned by userId.
///
/// The full domain model is stored as a JSON blob so domain-model evolution
/// never requires a migration — only the indexed lookup fields are columns.
@Model
public final class CachedBook {
    /// Composite unique key: "userId:bookId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    /// JSON-encoded BookCatalogItem.
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

extension CachedBook {
    static func makeRowId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }

    /// Creates a cache row from a domain model.
    public static func from(_ domain: BookCatalogItem, userId: String) throws -> CachedBook {
        let data = try JSONEncoder().encode(domain)
        return CachedBook(
            rowId: makeRowId(userId: userId, bookId: domain.bookId),
            userId: userId,
            bookId: domain.bookId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    /// Decodes back to the domain model. Throws if the stored JSON is corrupt.
    public func toDomain() throws -> BookCatalogItem {
        try JSONDecoder.chapterFlow.decode(BookCatalogItem.self, from: Data(dataJSON.utf8))
    }
}
