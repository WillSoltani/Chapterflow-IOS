import Foundation
import SwiftData
import Models

/// A cached ``NotebookEntry`` (note, bookmark, commitment, highlight, reflection).
///
/// `typeRaw` and `bookId` are extracted for efficient SwiftData queries.
/// The full `NotebookEntry` is stored as a JSON blob so `toDomain()` is lossless.
@Model
public final class CachedNotebookEntry {
    /// Composite unique key: "userId:entryId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    public var entryId: String
    /// NotebookEntryType raw value — stored for type-filtered queries without JSON decode.
    public var typeRaw: String
    /// JSON-encoded NotebookEntry for a lossless toDomain() reconstruction.
    public var dataJSON: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        entryId: String,
        typeRaw: String,
        dataJSON: String,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.entryId = entryId
        self.typeRaw = typeRaw
        self.dataJSON = dataJSON
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedNotebookEntry {
    static func makeRowId(userId: String, entryId: String) -> String {
        "\(userId):\(entryId)"
    }

    public static func from(_ domain: NotebookEntry, userId: String) throws -> CachedNotebookEntry {
        let data = try JSONEncoder().encode(domain)
        return CachedNotebookEntry(
            rowId: makeRowId(userId: userId, entryId: domain.entryId),
            userId: userId,
            bookId: domain.bookId,
            entryId: domain.entryId,
            typeRaw: domain.type.rawValue,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    public func toDomain() throws -> NotebookEntry {
        try JSONDecoder.chapterFlow.decode(NotebookEntry.self, from: Data(dataJSON.utf8))
    }
}
