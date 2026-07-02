#if DEBUG
import Models

/// Inline sample data for SwiftUI `#Preview` blocks.
enum QuizPreviewData {

    // MARK: - Choices & questions

    static let q1 = QuizQuestion(
        questionId: "q-1",
        prompt: "If you improve 1% each day for a year, how much better do you become?",
        choices: [
            QuizChoice(choiceId: "c-1-a", text: "About 4x better"),
            QuizChoice(choiceId: "c-1-b", text: "About 37x better"),
            QuizChoice(choiceId: "c-1-c", text: "About 365x better"),
            QuizChoice(choiceId: "c-1-d", text: "About 100x better"),
        ]
    )

    static let q2 = QuizQuestion(
        questionId: "q-2",
        prompt: "What is the 'valley of disappointment' in habit formation?",
        choices: [
            QuizChoice(choiceId: "c-2-a", text: "The period before results become visible"),
            QuizChoice(choiceId: "c-2-b", text: "The moment goals feel too ambitious"),
            QuizChoice(choiceId: "c-2-c", text: "The drop in motivation after a goal"),
            QuizChoice(choiceId: "c-2-d", text: "The phase where habits become boring"),
        ]
    )

    static let q3 = QuizQuestion(
        questionId: "q-3",
        prompt: "What is more effective for long-term success according to Atomic Habits?",
        choices: [
            QuizChoice(choiceId: "c-3-a", text: "Setting ambitious goals"),
            QuizChoice(choiceId: "c-3-b", text: "Building systems and processes"),
            QuizChoice(choiceId: "c-3-c", text: "Focusing on motivation and willpower"),
            QuizChoice(choiceId: "c-3-d", text: "Making large changes quickly"),
        ]
    )

    // MARK: - Session

    static let session = QuizClientSession(
        sessionId: "qs-ah-1-preview",
        questions: [q1, q2, q3],
        passingScorePercent: 70,
        bookId: "b-atomic-habits",
        chapterNumber: 1,
        tone: .direct
    )

    static let progress = BookProgress(
        currentChapterNumber: 1,
        unlockedThroughChapterNumber: 1,
        completedChapters: [],
        bestScoreByChapter: [:],
        preferredVariant: nil,
        progressRev: 1
    )

    static let quizResponse = QuizResponse(quiz: session, progress: progress)

    // MARK: - Results

    static let passedResult = QuizAttemptResult(
        passed: true,
        scorePercent: 100,
        correctCount: 3,
        totalQuestions: 3,
        cooldownSeconds: 0,
        nextEligibleAttemptAt: nil,
        unlockedNextChapter: true,
        questionResults: [
            QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-b",
                               correctChoiceId: "c-1-b", isCorrect: true),
            QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-a",
                               correctChoiceId: "c-2-a", isCorrect: true),
            QuizQuestionResult(questionId: "q-3", selectedChoiceId: "c-3-b",
                               correctChoiceId: "c-3-b", isCorrect: true),
        ]
    )

    static let failedResult = QuizAttemptResult(
        passed: false,
        scorePercent: 33,
        correctCount: 1,
        totalQuestions: 3,
        cooldownSeconds: 300,
        nextEligibleAttemptAt: nil,
        unlockedNextChapter: false,
        questionResults: [
            QuizQuestionResult(questionId: "q-1", selectedChoiceId: "c-1-a",
                               correctChoiceId: "c-1-b", isCorrect: false),
            QuizQuestionResult(questionId: "q-2", selectedChoiceId: "c-2-a",
                               correctChoiceId: "c-2-a", isCorrect: true),
            QuizQuestionResult(questionId: "q-3", selectedChoiceId: "c-3-c",
                               correctChoiceId: "c-3-b", isCorrect: false),
        ]
    )

    // MARK: - Fake repositories

    static var passRepo: FakeQuizRepository {
        FakeQuizRepository(quiz: quizResponse, submitResult: passedResult)
    }

    static var failRepo: FakeQuizRepository {
        FakeQuizRepository(quiz: quizResponse, submitResult: failedResult)
    }

    static var offlineRepo: FakeQuizRepository {
        FakeQuizRepository(error: .offline)
    }

    // MARK: - Pre-baked models (for result previews)

    @MainActor
    static func passedModel() -> QuizModel {
        let m = QuizModel(bookId: "b-atomic-habits", chapterNumber: 1, repository: passRepo)
        m.injectResultForPreview(session: session, result: passedResult)
        return m
    }

    @MainActor
    static func failedModel() -> QuizModel {
        let m = QuizModel(bookId: "b-atomic-habits", chapterNumber: 1, repository: failRepo)
        m.injectResultForPreview(session: session, result: failedResult, cooldownSeconds: 300)
        return m
    }

    @MainActor
    static func activeModel() -> QuizModel {
        let m = QuizModel(bookId: "b-atomic-habits", chapterNumber: 1, repository: passRepo)

        m.injectActiveForPreview(session: session, selectedAnswers: ["q-1": "c-1-b", "q-2": "c-2-a"])
        return m
    }
}
#endif
