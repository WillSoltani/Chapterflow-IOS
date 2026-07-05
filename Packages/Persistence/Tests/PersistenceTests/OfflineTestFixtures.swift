import Foundation
import Models
@testable import Persistence

// MARK: - Sample domain models for offline schema tests
// (internal access so they are visible to OfflineSchemaTests.swift in the same module)

let sampleBook = BookCatalogItem(
    bookId: "book-1",
    title: "Atomic Habits",
    author: "James Clear",
    categories: ["Self-Help"],
    tags: ["habits"],
    cover: Cover(emoji: "📚", color: "#FF6B35"),
    variantFamily: .emh,
    status: "published",
    latestVersion: 3,
    currentPublishedVersion: 3,
    updatedAt: "2024-01-01T00:00:00Z"
)

let sampleManifest = BookManifest(
    bookId: "book-1",
    title: "Atomic Habits",
    author: "James Clear",
    categories: ["Self-Help"],
    tags: ["habits"],
    cover: Cover(emoji: "📚", color: "#FF6B35"),
    variantFamily: .emh,
    status: "published",
    latestVersion: 3,
    currentPublishedVersion: 3,
    updatedAt: "2024-01-01T00:00:00Z",
    chapters: [
        BookManifestChapter(
            chapterId: "ch-1",
            number: 1,
            title: "The Surprising Power of Atomic Habits",
            readingTimeMinutes: 15,
            chapterKey: "ch-key-1",
            quizKey: "quiz-key-1"
        ),
    ],
    description: "A proven framework for improving every day.",
    shortDescription: "Build good habits.",
    totalReadingTimeMinutes: 210,
    chapterCount: 14
)

let sampleProgress = BookProgress(
    currentChapterNumber: 3,
    unlockedThroughChapterNumber: 3,
    completedChapters: [1, 2],
    bestScoreByChapter: ["1": 90, "2": 85],
    preferredVariant: .medium,
    progressRev: 7
)

let sampleBookState = BookStateResponse(
    state: BookUserBookState(
        currentChapterId: "ch-3",
        completedChapterIds: ["ch-1", "ch-2"],
        unlockedChapterIds: ["ch-1", "ch-2", "ch-3"],
        chapterScores: ["ch-1": 90, "ch-2": 85],
        chapterCompletedAt: ["ch-1": "2024-02-01T00:00:00Z"],
        lastReadChapterId: "ch-2",
        lastOpenedAt: "2024-02-10T08:00:00Z"
    ),
    applicationStates: ["ch-1": .committed, "ch-2": .applied]
)

let sampleQuiz = QuizClientSession(
    sessionId: "session-42",
    questions: [
        QuizQuestion(
            questionId: "q-1",
            prompt: "What is an atomic habit?",
            choices: [
                QuizChoice(choiceId: "c-1a", text: "A tiny habit"),
                QuizChoice(choiceId: "c-1b", text: "A large habit"),
            ]
        ),
    ],
    passingScorePercent: 70,
    bookId: "book-1",
    chapterNumber: 3,
    tone: .direct
)

let sampleNotebookEntry = NotebookEntry(
    entryId: "entry-1",
    bookId: "book-1",
    chapterId: "ch-2",
    type: .note,
    content: "My insight about habits",
    quote: nil,
    createdAt: "2024-02-01T00:00:00Z",
    updatedAt: "2024-02-01T00:00:00Z"
)

let sampleHighlightEntry = NotebookEntry(
    entryId: "highlight-1",
    bookId: "book-1",
    chapterId: "ch-1",
    type: .highlight,
    content: nil,
    quote: "Habits are the compound interest of self-improvement.",
    createdAt: "2024-02-01T00:00:00Z",
    updatedAt: "2024-02-01T00:00:00Z"
)

let sampleFsrsCard: FsrsCard = {
    let json = """
    {
      "cardId": "card-1",
      "bookId": "book-1",
      "chapterId": "ch-1",
      "front": "What is the habit loop?",
      "back": "Cue \\u2192 Craving \\u2192 Response \\u2192 Reward",
      "dueAt": "2024-03-15T08:00:00Z",
      "stability": 5.2,
      "difficulty": 4.1,
      "state": "review"
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder.chapterFlow.decode(FsrsCard.self, from: Data(json.utf8))
}()

let sampleChapter: Chapter = {
    let json = """
    {
      "chapterId": "ch-1",
      "number": 1,
      "title": "The Surprising Power of Atomic Habits",
      "readingTimeMinutes": 15,
      "activeVariant": "medium",
      "availableVariants": ["easy","medium","hard"],
      "content": {},
      "contentVariants": {"easy":{},"medium":{},"hard":{}},
      "examples": []
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder.chapterFlow.decode(Chapter.self, from: Data(json.utf8))
}()
