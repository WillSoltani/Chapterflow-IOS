import Foundation
import SwiftData
import Models

/// A cached full ``Chapter`` blob — includes ALL depth variants and tones.
///
/// Storing all variants lets the reader switch depth offline without a network
/// round-trip. The entire Chapter struct is JSON-encoded so domain-model
/// evolution never forces a migration.
@Model
public final class CachedChapter {
    /// Composite unique key: "userId:bookId:number".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    public var number: Int
    /// JSON-encoded Chapter (all contentVariants included).
    public var dataJSON: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        number: Int,
        dataJSON: String,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.number = number
        self.dataJSON = dataJSON
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedChapter {
    public static func makeRowId(userId: String, bookId: String, number: Int) -> String {
        "\(userId):\(bookId):\(number)"
    }

    /// Creates a cache row from a domain model.
    public static func from(
        _ domain: Chapter,
        userId: String,
        bookId: String
    ) throws -> CachedChapter {
        let data = try JSONEncoder().encode(domain)
        return CachedChapter(
            rowId: makeRowId(userId: userId, bookId: bookId, number: domain.number),
            userId: userId,
            bookId: bookId,
            number: domain.number,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    /// Decodes back to the domain model.
    public func toDomain() throws -> Chapter {
        try JSONDecoder.chapterFlow.decode(Chapter.self, from: Data(dataJSON.utf8))
    }
}
