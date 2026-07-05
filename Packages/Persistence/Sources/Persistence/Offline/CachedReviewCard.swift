import Foundation
import SwiftData
import Models

/// A cached FSRS spaced-repetition card with scheduling metadata.
///
/// `dueAt` is extracted from the server ISO-8601 string and stored as a `Date?`
/// so it can be indexed for efficient scheduling queries. The full ``FsrsCard``
/// is stored as a JSON blob for a lossless toDomain() reconstruction.
@Model
public final class CachedReviewCard {
    /// Composite unique key: "userId:cardId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var cardId: String
    public var bookId: String
    /// Parsed due date — indexed for scheduling queries.
    public var dueAt: Date?
    /// FsrsCardState raw value — stored for quick "due" filtering without JSON decode.
    public var stateRaw: String?
    /// JSON-encoded FsrsCard for a lossless toDomain() reconstruction.
    public var dataJSON: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        cardId: String,
        bookId: String,
        dueAt: Date? = nil,
        stateRaw: String? = nil,
        dataJSON: String,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.cardId = cardId
        self.bookId = bookId
        self.dueAt = dueAt
        self.stateRaw = stateRaw
        self.dataJSON = dataJSON
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedReviewCard {
    static func makeRowId(userId: String, cardId: String) -> String {
        "\(userId):\(cardId)"
    }

    public static func from(_ domain: FsrsCard, userId: String) throws -> CachedReviewCard {
        let dueAtDate: Date? = domain.dueAt.flatMap {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0))
                ?? (try? Date.ISO8601FormatStyle().parse($0))
        }
        let data = try JSONEncoder().encode(domain)
        return CachedReviewCard(
            rowId: makeRowId(userId: userId, cardId: domain.cardId),
            userId: userId,
            cardId: domain.cardId,
            bookId: domain.bookId,
            dueAt: dueAtDate,
            stateRaw: domain.state?.rawValue,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    public func toDomain() throws -> FsrsCard {
        try JSONDecoder.chapterFlow.decode(FsrsCard.self, from: Data(dataJSON.utf8))
    }
}
