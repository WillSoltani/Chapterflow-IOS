import Foundation

public extension Endpoints {
    // MARK: - Quiz Submit (SyncEngine outbox replay)

    /// `POST /book/me/quiz/{bookId}/{n}/submit` → `QuizAttemptResult`
    ///
    /// Replays an offline quiz submission. `sessionId` is the server-issued session
    /// ID used for idempotency — a duplicate submit with the same sessionId is
    /// detected server-side and treated as a no-op (returns the original result or
    /// an "already submitted" error, which the SyncEngine converts to success).
    ///
    /// - Parameters:
    ///   - bookId: The book the quiz belongs to.
    ///   - chapterNumber: The 1-based chapter number.
    ///   - sessionId: The server session ID from `QuizClientSession.sessionId`.
    ///   - answers: A mapping from `questionId` → `selectedChoiceId`.
    static func submitQuiz(
        bookId: String,
        chapterNumber: Int,
        sessionId: String,
        answers: [String: String]
    ) throws -> Endpoint {
        struct Body: Encodable {
            let sessionId: String
            let answers: [String: String]
        }
        let encodedBook = bookId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookId
        return try Endpoint(
            method: .post,
            path: "/book/me/quiz/\(encodedBook)/\(chapterNumber)/submit",
            body: Body(sessionId: sessionId, answers: answers)
        )
    }
}
