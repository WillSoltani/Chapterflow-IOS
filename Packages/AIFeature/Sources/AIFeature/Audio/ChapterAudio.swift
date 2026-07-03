/// Server response for `GET /book/books/{bookId}/chapters/{n}/audio`.
struct ChapterAudio: Codable, Sendable {
    /// A signed, time-limited URL pointing to the chapter's audio file in S3.
    let url: String
}
