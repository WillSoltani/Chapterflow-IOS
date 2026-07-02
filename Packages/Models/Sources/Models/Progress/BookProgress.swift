/// A user's numeric reading progress through a book.
///
/// Part of the response from `GET /book/books/{bookId}/chapters/{n}` and
/// `GET /book/me/progress/{bookId}`.
public struct BookProgress: Codable, Sendable {
    public let currentChapterNumber: Int
    public let unlockedThroughChapterNumber: Int
    public let completedChapters: [Int]
    public let bestScoreByChapter: [String: Int]
    public let preferredVariant: VariantKey?
    public let progressRev: Int?
}
