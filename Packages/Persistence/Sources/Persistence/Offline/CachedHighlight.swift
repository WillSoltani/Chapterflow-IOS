import Foundation
import SwiftData
import Models

/// A cached reader highlight backed by a server ``NotebookEntry`` of type "highlight".
///
/// The domain model is stored as a JSON blob for lossless round-trips. Two
/// reader-specific columns (colorRaw, anchorJSON) extend the domain model with
/// data the reader layer writes after insertion; they are not part of NotebookEntry.
@Model
public final class CachedHighlight {
    /// Composite unique key: "userId:bookId:entryId".
    @Attribute(.unique) public var rowId: String
    public var userId: String
    public var bookId: String
    public var chapterId: String?
    /// The server-assigned notebook entryId (also stored in dataJSON).
    public var entryId: String
    /// Highlight colour token, e.g. "yellow". Set by the reader layer; not in NotebookEntry.
    public var colorRaw: String?
    /// JSON-encoded selection anchor. Set by the reader layer; not in NotebookEntry.
    public var anchorJSON: String?
    /// JSON-encoded NotebookEntry for a lossless toDomain() reconstruction.
    public var dataJSON: String
    public var cachedAt: Date

    public init(
        rowId: String,
        userId: String,
        bookId: String,
        chapterId: String? = nil,
        entryId: String,
        colorRaw: String? = nil,
        anchorJSON: String? = nil,
        dataJSON: String,
        cachedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.userId = userId
        self.bookId = bookId
        self.chapterId = chapterId
        self.entryId = entryId
        self.colorRaw = colorRaw
        self.anchorJSON = anchorJSON
        self.dataJSON = dataJSON
        self.cachedAt = cachedAt
    }
}

// MARK: - Domain mapping

extension CachedHighlight {
    static func makeRowId(userId: String, bookId: String, entryId: String) -> String {
        "\(userId):\(bookId):\(entryId)"
    }

    /// Creates a highlight row from a NotebookEntry with type "highlight".
    ///
    /// The reader-specific fields (colorRaw, anchorJSON) default to nil; the
    /// reader layer can set them on the returned row before persisting.
    public static func from(_ domain: NotebookEntry, userId: String) throws -> CachedHighlight {
        let data = try JSONEncoder().encode(domain)
        return CachedHighlight(
            rowId: makeRowId(userId: userId, bookId: domain.bookId, entryId: domain.entryId),
            userId: userId,
            bookId: domain.bookId,
            chapterId: domain.chapterId,
            entryId: domain.entryId,
            dataJSON: String(bytes: data, encoding: .utf8) ?? ""
        )
    }

    /// Reconstructs the ``NotebookEntry`` domain model losslessly.
    ///
    /// The reader-only fields (colorRaw, anchorJSON) are not present in
    /// NotebookEntry and are not included in the returned domain model.
    public func toDomain() throws -> NotebookEntry {
        try JSONDecoder.chapterFlow.decode(NotebookEntry.self, from: Data(dataJSON.utf8))
    }
}
