/// The type of a notebook entry.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views should hide or show a generic icon for `.unknown` entries.
public enum NotebookEntryType: Sendable, Equatable, Hashable {
    case note
    case reflection
    case bookmark
    case commitment
    case highlight
    /// An entry type the client does not recognise. Render generically; never crash.
    case unknown(String)
}

extension NotebookEntryType: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .note:           return "note"
        case .reflection:     return "reflection"
        case .bookmark:       return "bookmark"
        case .commitment:     return "commitment"
        case .highlight:      return "highlight"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "note":       self = .note
        case "reflection": self = .reflection
        case "bookmark":   self = .bookmark
        case "commitment": self = .commitment
        case "highlight":  self = .highlight
        default:           self = .unknown(rawValue)
        }
    }
}

extension NotebookEntryType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = NotebookEntryType(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension NotebookEntryType: CaseIterable {
    public static var allCases: [NotebookEntryType] {
        [.note, .reflection, .bookmark, .commitment, .highlight]
    }
}

// MARK: - NotebookEntry

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

// MARK: - NotebookResponse

/// Response from `GET /book/me/notebook`.
/// Decodes the `entries` array lossily — one malformed entry is dropped and
/// logged while the rest of the list survives.
public struct NotebookResponse: Codable, Sendable {
    public let entries: [NotebookEntry]

    private enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try container.decodeLossy(NotebookEntry.self, forKey: .entries)
    }
}
