import Models

extension Fixtures {

    // MARK: - Quiz session

    /// Quiz session + progress for Atomic Habits ch. 1 (3 questions).
    ///
    /// One question uses the `prompt` key; one uses the legacy `stem` key —
    /// exercises the `QuizQuestion` unified decoder.
    public static let quizSession: QuizResponse = load("quiz")

    /// Raw `QuizClientSession` from the quiz response.
    public static var quiz: QuizClientSession { quizSession.quiz }

    // MARK: - Graded result

    /// A passing quiz result: 3/3 correct, all chapters unlocked.
    public static let quizResultPassed: QuizAttemptResult = load("quiz_result")

    /// A failing quiz result: 1/3 correct, cooldown active (5 min).
    public static let quizResultFailed: QuizAttemptResult = load("quiz_result_failed")
}
