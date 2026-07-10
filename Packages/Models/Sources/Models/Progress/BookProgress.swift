/// A user's numeric reading progress through a book.
///
/// Part of the response from `GET /book/books/{bookId}/chapters/{n}` and
/// `GET /book/me/progress/{bookId}`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed chapter/quiz routes send a TRIMMED projection — only
/// `currentChapterNumber`, `unlockedThroughChapterNumber`, and
/// `completedChapters` — omitting `bestScoreByChapter` entirely. Every field
/// therefore defaults instead of throwing; gating truth stays server-side.
public struct BookProgress: Codable, Sendable {
    public let currentChapterNumber: Int
    public let unlockedThroughChapterNumber: Int
    public let completedChapters: [Int]
    public let bestScoreByChapter: [String: Int]
    public let preferredVariant: VariantKey?
    public let progressRev: Int?

    public init(
        currentChapterNumber: Int,
        unlockedThroughChapterNumber: Int,
        completedChapters: [Int],
        bestScoreByChapter: [String: Int],
        preferredVariant: VariantKey?,
        progressRev: Int?
    ) {
        self.currentChapterNumber = currentChapterNumber
        self.unlockedThroughChapterNumber = unlockedThroughChapterNumber
        self.completedChapters = completedChapters
        self.bestScoreByChapter = bestScoreByChapter
        self.preferredVariant = preferredVariant
        self.progressRev = progressRev
    }

    private enum WireKeys: String, CodingKey {
        case currentChapterNumber, unlockedThroughChapterNumber
        case completedChapters, bestScoreByChapter
        case preferredVariant, progressRev
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        currentChapterNumber = c.decodeFirst(Int.self, keys: [.currentChapterNumber]) ?? 1
        unlockedThroughChapterNumber =
            c.decodeFirst(Int.self, keys: [.unlockedThroughChapterNumber]) ?? 1
        completedChapters = c.decodeFirst([Int].self, keys: [.completedChapters]) ?? []
        bestScoreByChapter = c.decodeFirst([String: Int].self, keys: [.bestScoreByChapter]) ?? [:]
        preferredVariant = c.decodeFirst(VariantKey.self, keys: [.preferredVariant])
        progressRev = c.decodeFirst(Int.self, keys: [.progressRev])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(currentChapterNumber, forKey: .currentChapterNumber)
        try c.encode(unlockedThroughChapterNumber, forKey: .unlockedThroughChapterNumber)
        try c.encode(completedChapters, forKey: .completedChapters)
        try c.encode(bestScoreByChapter, forKey: .bestScoreByChapter)
        try c.encodeIfPresent(preferredVariant, forKey: .preferredVariant)
        try c.encodeIfPresent(progressRev, forKey: .progressRev)
    }
}
