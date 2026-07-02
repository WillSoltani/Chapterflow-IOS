import Foundation
import Models
import Networking

/// Production ``QuizRepository`` backed by the ChapterFlow REST API.
public actor LiveQuizRepository: QuizRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func getQuiz(bookId: String, n: Int, tone: ToneKey?) async throws -> QuizResponse {
        try await client.send(Endpoints.getQuiz(bookId: bookId, n: n, tone: tone?.rawValue))
    }

    public func submit(bookId: String, n: Int, answers: [QuizAnswerSubmission]) async throws -> QuizAttemptResult {
        let endpoint = try Endpoints.submitQuiz(bookId: bookId, n: n, answers: answers)
        return try await client.send(endpoint)
    }

    public func check(bookId: String, n: Int, questionId: String, choiceId: String) async throws -> QuizCheckResult {
        let endpoint = try Endpoints.checkQuizAnswer(
            bookId: bookId, n: n,
            questionId: questionId, choiceId: choiceId
        )
        return try await client.send(endpoint)
    }

    public func postEvent(bookId: String, n: Int, event: QuizEventPayload) async throws {
        let endpoint = try Endpoints.postQuizEvent(bookId: bookId, n: n, event: event)
        let _: QuizEventAck = try await client.send(endpoint)
    }
}
