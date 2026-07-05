import Foundation
import SwiftData
import Models

/// A cached ``BookProgress`` snapshot — server-owned; never mutated locally.
///
/// Gating fields (`unlockedThroughChapterNumber`, `completedChapters`,
/// `bestScoreByChapter`) are read-only cache: write the whole row only when a
/// fresh server response arrives. Never increment locally.
@Model
public final class CachedProgress {
    /// Composite unique key: "userId:bookId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    /// JSON-encoded BookProgress (all gating fields preserved verbatim).
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

extension CachedProgress {
    static func makeRowId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }

    public static func from(_ domain: BookProgress, userId: String, bookId: String) throws -> CachedProgress {
        let data = try JSONEncoder().encode(domain)
        return CachedProgress(
            rowId: makeRowId(userId: userId, bookId: bookId),
            userId: userId,
            bookId: bookId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    public func toDomain() throws -> BookProgress {
        try JSONDecoder.chapterFlow.decode(BookProgress.self, from: Data(dataJSON.utf8))
    }
}
