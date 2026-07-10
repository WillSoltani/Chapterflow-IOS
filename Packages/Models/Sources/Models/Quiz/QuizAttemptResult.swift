/// The server-graded result of a quiz attempt.
///
/// Returned by `POST /book/me/quiz/{bookId}/{n}/submit`.
/// This is always authoritative — never grade client-side.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed submit route does NOT return this flat shape — it returns
/// `{quiz: <client session>, progress: {…}}` where the grade lives in
/// `quiz.result` (`{attemptNumber, scorePercent, correctAnswers,
/// totalQuestions, passed, submittedAt}`), the retry rule in
/// `quiz.cooldownSeconds`/`quiz.nextAttemptAvailableAt`/`quiz.unlockedNextChapter`,
/// and per-question grades on `quiz.questions[]`
/// (`selectedChoiceId`/`correctChoiceId`/`isCorrect`, revealed post-submit).
/// This initializer decodes EITHER the canonical flat shape OR that deployed
/// envelope. Every grading fact still comes from server-marked fields — the
/// client never grades.
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

    private enum WireKeys: String, CodingKey {
        case passed, scorePercent, correctCount, totalQuestions
        case cooldownSeconds, nextEligibleAttemptAt, unlockedNextChapter, questionResults
        case quiz
    }

    /// Keys inside the deployed `{quiz: …}` session envelope.
    private enum SessionK: String, CodingKey {
        case result, questions, status
        case cooldownSeconds, nextAttemptAvailableAt, unlockedNextChapter
    }

    private enum ResultK: String, CodingKey {
        case passed, scorePercent, correctAnswers, correctCount, totalQuestions
    }

    public init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: WireKeys.self)

        // Deployed envelope: {quiz: {result, questions, cooldownSeconds, …}}.
        if root.contains(.quiz),
           let quiz = try? root.nestedContainer(keyedBy: SessionK.self, forKey: .quiz) {
            let result = try? quiz.nestedContainer(keyedBy: ResultK.self, forKey: .result)
            let questions =
                (try? quiz.decodeLossy(SessionQuestionGrade.self, forKey: .questions)) ?? []
            let gradedResults = questions.compactMap(\.asQuestionResult)
            let status = quiz.decodeFirst(String.self, keys: [.status])

            let serverCorrect = result.flatMap {
                $0.decodeFirst(Int.self, keys: [.correctAnswers, .correctCount])
            }
            let serverTotal = result.flatMap { $0.decodeFirst(Int.self, keys: [.totalQuestions]) }
            let derivedCorrect = gradedResults.filter(\.isCorrect).count

            passed = result.flatMap { $0.decodeFirst(Bool.self, keys: [.passed]) }
                ?? (status == "passed")
            correctCount = serverCorrect ?? derivedCorrect
            totalQuestions = serverTotal ?? max(questions.count, gradedResults.count)
            if let score = result.flatMap({ $0.decodeFirst(Int.self, keys: [.scorePercent]) }) {
                scorePercent = score
            } else if totalQuestions > 0 {
                scorePercent = Int(
                    (Double(correctCount) / Double(totalQuestions) * 100).rounded())
            } else {
                scorePercent = 0
            }
            cooldownSeconds = quiz.decodeFirst(Int.self, keys: [.cooldownSeconds]) ?? 0
            nextEligibleAttemptAt = quiz.decodeFirst(
                String.self, keys: [.nextAttemptAvailableAt])
            unlockedNextChapter =
                quiz.decodeFirst(Bool.self, keys: [.unlockedNextChapter]) ?? false
            questionResults = gradedResults
            return
        }

        // Canonical flat shape (caches, fixtures, future server versions).
        passed = root.decodeFirst(Bool.self, keys: [.passed]) ?? false
        scorePercent = root.decodeFirst(Int.self, keys: [.scorePercent]) ?? 0
        correctCount = root.decodeFirst(Int.self, keys: [.correctCount]) ?? 0
        totalQuestions = root.decodeFirst(Int.self, keys: [.totalQuestions]) ?? 0
        cooldownSeconds = root.decodeFirst(Int.self, keys: [.cooldownSeconds]) ?? 0
        nextEligibleAttemptAt = root.decodeFirst(String.self, keys: [.nextEligibleAttemptAt])
        unlockedNextChapter = root.decodeFirst(Bool.self, keys: [.unlockedNextChapter]) ?? false
        questionResults =
            (try? root.decodeLossy(QuizQuestionResult.self, forKey: .questionResults)) ?? []
    }

    /// Always encodes the canonical flat shape.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(passed, forKey: .passed)
        try c.encode(scorePercent, forKey: .scorePercent)
        try c.encode(correctCount, forKey: .correctCount)
        try c.encode(totalQuestions, forKey: .totalQuestions)
        try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try c.encodeIfPresent(nextEligibleAttemptAt, forKey: .nextEligibleAttemptAt)
        try c.encode(unlockedNextChapter, forKey: .unlockedNextChapter)
        try c.encode(questionResults, forKey: .questionResults)
    }

    /// A deployed session question carrying post-submit grade fields.
    private struct SessionQuestionGrade: Decodable {
        let questionId: String
        let selectedChoiceId: String?
        let correctChoiceId: String?
        let isCorrect: Bool?

        /// Converts to a `QuizQuestionResult` when the server revealed a grade
        /// for this question (post-submit projection). Ungraded questions
        /// (`isCorrect` withheld) produce nil and are omitted.
        var asQuestionResult: QuizQuestionResult? {
            guard let isCorrect else { return nil }
            return QuizQuestionResult(
                questionId: questionId,
                selectedChoiceId: selectedChoiceId,
                correctChoiceId: correctChoiceId ?? "",
                isCorrect: isCorrect)
        }
    }
}

/// The grade for a single question within a quiz attempt.
///
/// `correctChoiceId` can be empty ("") when the server withheld the answer key
/// (it reveals keys only on post-submit review projections) — treat empty as
/// "no reveal", never as a real choice id.
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

    private enum WireKeys: String, CodingKey {
        case questionId, selectedChoiceId, correctChoiceId, isCorrect
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        questionId = try c.decodeRequiredFirst(String.self, keys: [.questionId])
        selectedChoiceId = c.decodeFirst(String.self, keys: [.selectedChoiceId])
        correctChoiceId = c.decodeFirst(String.self, keys: [.correctChoiceId]) ?? ""
        isCorrect = c.decodeFirst(Bool.self, keys: [.isCorrect]) ?? false
    }
}
