import Foundation
import SwiftData
import Models

/// A cached ``BookStateResponse`` — server-owned chapter-level state.
///
/// Stores which chapters are unlocked/completed/scored. These are gating fields;
/// they are cached verbatim from the server and never mutated locally.
@Model
public final class CachedBookState {
    /// Composite unique key: "userId:bookId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    /// JSON-encoded BookStateResponse (state + applicationStates).
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

extension CachedBookState {
    static func makeRowId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }

    public static func from(
        _ domain: BookStateResponse,
        userId: String,
        bookId: String
    ) throws -> CachedBookState {
        let data = try JSONEncoder().encode(domain)
        return CachedBookState(
            rowId: makeRowId(userId: userId, bookId: bookId),
            userId: userId,
            bookId: bookId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    public func toDomain() throws -> BookStateResponse {
        try JSONDecoder.chapterFlow.decode(BookStateResponse.self, from: Data(dataJSON.utf8))
    }
}
