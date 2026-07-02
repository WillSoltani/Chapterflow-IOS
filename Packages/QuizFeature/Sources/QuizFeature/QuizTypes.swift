import Foundation

// MARK: - Submission

/// A single selected answer to be sent to the server.
public struct QuizAnswerSubmission: Codable, Sendable, Equatable {
    public let questionId: String
    public let choiceId: String

    public init(questionId: String, choiceId: String) {
        self.questionId = questionId
        self.choiceId = choiceId
    }
}

/// The request body for `POST .../submit`.
struct QuizSubmitRequest: Encodable, Sendable {
    let answers: [QuizAnswerSubmission]
}

// MARK: - Single-answer check

/// The request body for `POST .../check`.
struct QuizCheckRequest: Encodable, Sendable {
    let questionId: String
    let choiceId: String
}

/// The server's verdict on a single-question check.
public struct QuizCheckResult: Decodable, Sendable {
    public let isCorrect: Bool
    public let correctChoiceId: String
}

// MARK: - Events

/// Payload for a quiz lifecycle event (analytics / server-side tracking).
public struct QuizEventPayload: Encodable, Sendable {
    public let eventType: String
    public let questionId: String?

    public init(eventType: String, questionId: String? = nil) {
        self.eventType = eventType
        self.questionId = questionId
    }
}

/// Loosely-typed acknowledgement from the events endpoint.
/// The server may return `{}` or a minimal JSON object; we accept anything.
struct QuizEventAck: Decodable, Sendable {
    // Intentionally empty — any decodable JSON object is accepted.
    init(from decoder: Decoder) throws {}
}
