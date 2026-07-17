import Foundation

/// Stable deterministic IDs for reader-annotation journal rows.
public enum AnnotationMutationID {
    public static func create(localAnnotationId: String) -> String {
        "annotation-create:\(localAnnotationId)"
    }

    public static func delete(localAnnotationId: String) -> String {
        "annotation-delete:\(localAnnotationId)"
    }
}

/// Persistence-owned copy of the verified notebook anchor wire shape.
public struct NotebookAnchorPayload: Codable, Sendable, Equatable {
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

/// Payload for ``MutationKind/notebookWrite`` (notes and bookmarks).
public struct NotebookWritePayload: Codable, Sendable, Equatable {
    /// Non-nil means update the existing entry; nil means create new.
    public let entryId: String?
    /// Local reader row reconciled after a create. Nil for legacy/non-reader producers.
    public let localAnnotationId: String?
    public let bookId: String
    public let chapterId: String
    /// `note` or `bookmark`.
    public let type: String
    public let content: String?
    public let quote: String?
    public let color: String?
    public let anchor: NotebookAnchorPayload?

    public init(
        entryId: String? = nil,
        localAnnotationId: String? = nil,
        bookId: String,
        chapterId: String,
        type: String,
        content: String? = nil,
        quote: String? = nil,
        color: String? = nil,
        anchor: NotebookAnchorPayload? = nil
    ) {
        self.entryId = entryId
        self.localAnnotationId = localAnnotationId
        self.bookId = bookId
        self.chapterId = chapterId
        self.type = type
        self.content = content
        self.quote = quote
        self.color = color
        self.anchor = anchor
    }
}

/// Payload for ``MutationKind/highlightWrite``.
public struct HighlightWritePayload: Codable, Sendable, Equatable {
    /// Non-nil means update the existing entry; nil means create new.
    public let entryId: String?
    /// Local reader row reconciled after a create. Nil for legacy/non-reader producers.
    public let localAnnotationId: String?
    public let bookId: String
    public let chapterId: String
    public let variantKey: String
    public let toneKey: String
    public let blockIndex: Int
    public let blockType: String
    public let startChar: Int
    public let endChar: Int
    public let snippet: String
    public let color: String

    public init(
        entryId: String? = nil,
        localAnnotationId: String? = nil,
        bookId: String,
        chapterId: String,
        variantKey: String,
        toneKey: String,
        blockIndex: Int,
        blockType: String,
        startChar: Int,
        endChar: Int,
        snippet: String,
        color: String
    ) {
        self.entryId = entryId
        self.localAnnotationId = localAnnotationId
        self.bookId = bookId
        self.chapterId = chapterId
        self.variantKey = variantKey
        self.toneKey = toneKey
        self.blockIndex = blockIndex
        self.blockType = blockType
        self.startChar = startChar
        self.endChar = endChar
        self.snippet = snippet
        self.color = color
    }
}

/// Payload for ``MutationKind/notebookDelete``.
public struct NotebookDeletePayload: Codable, Sendable, Equatable {
    public let localAnnotationId: String
    public let serverEntryId: String

    public init(localAnnotationId: String, serverEntryId: String) {
        self.localAnnotationId = localAnnotationId
        self.serverEntryId = serverEntryId
    }
}
