/// The server-graded result of a quiz attempt.
///
/// Returned by `POST /book/me/quiz/{bookId}/{n}/submit`.
/// This is always authoritative — never grade client-side.
public struct QuizAttemptResult: Codable, Sendable {
    public let passed: Bool
    public let scorePercent: Int
    public let correctCount: Int
    public let totalQuestions: Int
    public let cooldownSeconds: Int
    public let nextEligibleAttemptAt: String?
    public let unlockedNextChapter: Bool
    public let questionResults: [QuizQuestionResult]
}

/// The grade for a single question within a quiz attempt.
public struct QuizQuestionResult: Codable, Sendable {
    public let questionId: String
    public let selectedChoiceId: String?
    public let correctChoiceId: String
    public let isCorrect: Bool
}
