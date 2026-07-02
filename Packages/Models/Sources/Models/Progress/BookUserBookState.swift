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
public enum ChapterApplicationState: String, Codable, Sendable, CaseIterable {
    case none
    case committed
    case applied
}

/// The full state response, combining per-book state with per-chapter application states.
public struct BookStateResponse: Codable, Sendable {
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?
}
