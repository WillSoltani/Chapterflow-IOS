/// The user's chapter-level state for a book: which chapters are unlocked,
/// completed, scored, and when they were last touched.
///
/// Returned (with `applicationStates`) by `GET|PATCH /book/me/books/{bookId}/state`.
public struct BookUserBookState: Codable, Sendable {
    public let currentChapterId: String?
    public let completedChapterIds: [String]
    public let unlockedChapterIds: [String]
    public let chapterScores: [String: Int]
    public let chapterCompletedAt: [String: String]
    public let lastReadChapterId: String?
    public let lastOpenedAt: String?
}

/// Per-chapter "applied" state — whether the user committed to or applied a chapter's plan.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views should treat `.unknown` as `.none`.
public enum ChapterApplicationState: Sendable, Equatable, Hashable {
    case none
    case committed
    case applied
    /// A state the client does not recognise. Treat as `.none`; never crash.
    case unknown(String)
}

extension ChapterApplicationState: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .none:           return "none"
        case .committed:      return "committed"
        case .applied:        return "applied"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "none":      self = .none
        case "committed": self = .committed
        case "applied":   self = .applied
        default:          self = .unknown(rawValue)
        }
    }
}

extension ChapterApplicationState: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ChapterApplicationState(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ChapterApplicationState: CaseIterable {
    public static var allCases: [ChapterApplicationState] { [.none, .committed, .applied] }
}

/// The full state response, combining per-book state with per-chapter application states.
public struct BookStateResponse: Codable, Sendable {
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?
}
