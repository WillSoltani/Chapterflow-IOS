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

    public init(
        passed: Bool,
        scorePercent: Int,
        correctCount: Int,
        totalQuestions: Int,
        cooldownSeconds: Int,
        nextEligibleAttemptAt: String?,
        unlockedNextChapter: Bool,
        questionResults: [QuizQuestionResult]
    ) {
        self.passed = passed
        self.scorePercent = scorePercent
        self.correctCount = correctCount
        self.totalQuestions = totalQuestions
        self.cooldownSeconds = cooldownSeconds
        self.nextEligibleAttemptAt = nextEligibleAttemptAt
        self.unlockedNextChapter = unlockedNextChapter
        self.questionResults = questionResults
    }
}

/// The grade for a single question within a quiz attempt.
public struct QuizQuestionResult: Codable, Sendable {
    public let questionId: String
    public let selectedChoiceId: String?
    public let correctChoiceId: String
    public let isCorrect: Bool

    public init(questionId: String, selectedChoiceId: String?, correctChoiceId: String, isCorrect: Bool) {
        self.questionId = questionId
        self.selectedChoiceId = selectedChoiceId
        self.correctChoiceId = correctChoiceId
        self.isCorrect = isCorrect
    }
}
