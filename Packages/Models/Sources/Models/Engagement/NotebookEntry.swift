/// The type of a notebook entry.
public enum NotebookEntryType: String, Codable, Sendable, CaseIterable {
    case note
    case reflection
    case bookmark
    case commitment
    case highlight
}

/// A single entry in the user's notebook (note, bookmark, highlight, etc.).
///
/// Returned within `GET /book/me/notebook`.
public struct NotebookEntry: Codable, Sendable, Identifiable {
    public let entryId: String
    public let bookId: String
    public let chapterId: String?
    public let type: NotebookEntryType
    /// The user-written text (notes, reflections, commitments).
    public let content: String?
    /// The quoted passage (highlights, bookmarks).
    public let quote: String?
    public let createdAt: String
    public let updatedAt: String

    public var id: String { entryId }
}

public struct NotebookResponse: Codable, Sendable {
    public let entries: [NotebookEntry]
}
