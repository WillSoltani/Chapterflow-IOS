import Foundation
import Networking

extension Endpoints {
    /// `POST /book/me/quiz/{bookId}/{n}/submit`
    ///
    /// Submit all selected answers and receive the server-graded ``QuizAttemptResult``.
    /// **Never grade answers client-side — this endpoint is the sole source of truth.**
    public static func submitQuiz(
        bookId: String,
        n: Int,
        answers: [QuizAnswerSubmission]
    ) throws -> Endpoint {
        try Endpoint(
            method: .post,
            path: "/book/me/quiz/\(bookId)/\(n)/submit",
            body: QuizSubmitRequest(answers: answers)
        )
    }

    /// `POST /book/books/{bookId}/chapters/{n}/quiz/check`
    ///
    /// Verify a single answer in real-time (used for step-through quiz modes).
    public static func checkQuizAnswer(
        bookId: String,
        n: Int,
        questionId: String,
        choiceId: String
    ) throws -> Endpoint {
        try Endpoint(
            method: .post,
            path: "/book/books/\(bookId)/chapters/\(n)/quiz/check",
            body: QuizCheckRequest(questionId: questionId, choiceId: choiceId)
        )
    }

    /// `POST /book/me/quiz/{bookId}/{n}/events`
    ///
    /// Post a quiz lifecycle event for server-side analytics / progress tracking.
    public static func postQuizEvent(
        bookId: String,
        n: Int,
        event: QuizEventPayload
    ) throws -> Endpoint {
        try Endpoint(
            method: .post,
            path: "/book/me/quiz/\(bookId)/\(n)/events",
            body: event
        )
    }
}
