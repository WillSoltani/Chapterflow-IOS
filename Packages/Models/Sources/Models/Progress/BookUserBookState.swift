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

    public init(
        currentChapterId: String?,
        completedChapterIds: [String],
        unlockedChapterIds: [String],
        chapterScores: [String: Int],
        chapterCompletedAt: [String: String],
        lastReadChapterId: String?,
        lastOpenedAt: String?
    ) {
        self.currentChapterId = currentChapterId
        self.completedChapterIds = completedChapterIds
        self.unlockedChapterIds = unlockedChapterIds
        self.chapterScores = chapterScores
        self.chapterCompletedAt = chapterCompletedAt
        self.lastReadChapterId = lastReadChapterId
        self.lastOpenedAt = lastOpenedAt
    }
}

/// Authoritative started/not-started status returned by
/// `GET /book/me/books/{bookId}/state`.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Consumers must not infer a known status from the synthesized
/// state payload when this value is unknown.
public enum BookStateStatus: Sendable, Equatable, Hashable {
    case started
    case notStarted
    case unknown(String)
}

extension BookStateStatus: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .started:           return "started"
        case .notStarted:        return "not_started"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "started":     self = .started
        case "not_started": self = .notStarted
        default:              self = .unknown(rawValue)
        }
    }
}

extension BookStateStatus: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = BookStateStatus(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension BookStateStatus: CaseIterable {
    public static var allCases: [BookStateStatus] { [.started, .notStarted] }
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

    public init(state: BookUserBookState, applicationStates: [String: ChapterApplicationState]?) {
        self.state = state
        self.applicationStates = applicationStates
    }
}

/// Dedicated response for `GET /book/me/books/{bookId}/state`.
///
/// `stateStatus` is optional for compatibility with a deployed backend that may not
/// emit the additive field yet. A missing value is compatibility-unknown; callers
/// must not infer started/not-started from `state`.
///
/// Start/PATCH responses intentionally continue using ``BookStateResponse`` because
/// those routes do not share this GET-only authority field.
public struct BookStateGetResponse: Codable, Sendable {
    public let stateStatus: BookStateStatus?
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?

    public init(
        stateStatus: BookStateStatus?,
        state: BookUserBookState,
        applicationStates: [String: ChapterApplicationState]?
    ) {
        self.stateStatus = stateStatus
        self.state = state
        self.applicationStates = applicationStates
    }
}
