import Foundation

/// Request body for `POST /book/me/notebook`.
///
/// Used by the annotation feature to create highlights, notes, and bookmarks.
/// The anchor is optional — standalone bookmarks omit it.
public struct NotebookEntryRequest: Codable, Sendable {

    /// Anchor payload describing where in the chapter the annotation lives.
    public struct Anchor: Codable, Sendable {
        public let variantKey: String
        public let toneKey: String
        public let blockIndex: Int
        public let blockType: String
        public let startChar: Int
        public let endChar: Int
        public let snippet: String

        public init(
            variantKey: String,
            toneKey: String,
            blockIndex: Int,
            blockType: String,
            startChar: Int,
            endChar: Int,
            snippet: String
        ) {
            self.variantKey = variantKey
            self.toneKey = toneKey
            self.blockIndex = blockIndex
            self.blockType = blockType
            self.startChar = startChar
            self.endChar = endChar
            self.snippet = snippet
        }
    }

    public let bookId: String
    public let chapterId: String
    /// "highlight" | "note" | "bookmark"
    public let type: String
    /// User-written text (notes only).
    public let content: String?
    /// The quoted passage (highlights and bookmarks with a selection).
    public let quote: String?
    /// The highlight colour raw value (e.g. "yellow").
    public let color: String?
    /// Where in the chapter the annotation was made.
    public let anchor: Anchor?

    public init(
        bookId: String,
        chapterId: String,
        type: String,
        content: String? = nil,
        quote: String? = nil,
        color: String? = nil,
        anchor: Anchor? = nil
    ) {
        self.bookId = bookId
        self.chapterId = chapterId
        self.type = type
        self.content = content
        self.quote = quote
        self.color = color
        self.anchor = anchor
    }
}

/// Minimal response from `POST /book/me/notebook`.
public struct NotebookCreateResponse: Codable, Sendable {
    public let entryId: String

    public init(entryId: String) {
        self.entryId = entryId
    }
}

/// Response from `DELETE /book/me/notebook/{entryId}`.
public struct NotebookDeleteResponse: Codable, Sendable {
    public let deleted: Bool?

    public init(deleted: Bool? = nil) {
        self.deleted = deleted
    }
}
