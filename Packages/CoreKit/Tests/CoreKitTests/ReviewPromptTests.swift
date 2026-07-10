import Testing
import Foundation
@testable import CoreKit

// MARK: - Policy (pure rule)

@Suite("ReviewPromptPolicy")
struct ReviewPromptPolicyTests {

    @Test("passing a quiz on a 3+ day streak (new version) prompts")
    func quizPassOnStreakPrompts() {
        #expect(ReviewPromptPolicy.shouldRequestReview(
            for: .quizCompleted(passed: true, currentStreakDays: 3),
            currentVersion: "1.2",
            lastPromptedVersion: nil
        ))
    }

    @Test("a longer streak still prompts")
    func longerStreakPrompts() {
        #expect(ReviewPromptPolicy.shouldRequestReview(
            for: .quizCompleted(passed: true, currentStreakDays: 42),
            currentVersion: "1.2",
            lastPromptedVersion: "1.1"
        ))
    }

    @Test("passing a quiz below the streak threshold does not prompt")
    func quizPassBelowStreakDoesNotPrompt() {
        for streak in 0..<ReviewPromptPolicy.minimumStreakForQuizPrompt {
            #expect(!ReviewPromptPolicy.shouldRequestReview(
                for: .quizCompleted(passed: true, currentStreakDays: streak),
                currentVersion: "1.2",
                lastPromptedVersion: nil
            ))
        }
    }

    @Test("never prompts after a failed quiz, even on a long streak")
    func failedQuizNeverPrompts() {
        #expect(!ReviewPromptPolicy.shouldRequestReview(
            for: .quizCompleted(passed: false, currentStreakDays: 30),
            currentVersion: "1.2",
            lastPromptedVersion: nil
        ))
    }

    @Test("finishing a book prompts on a fresh version")
    func bookFinishedPrompts() {
        #expect(ReviewPromptPolicy.shouldRequestReview(
            for: .bookFinished,
            currentVersion: "1.2",
            lastPromptedVersion: "1.1"
        ))
    }

    @Test("never prompts twice on the same version")
    func sameVersionNeverPromptsAgain() {
        #expect(!ReviewPromptPolicy.shouldRequestReview(
            for: .bookFinished,
            currentVersion: "1.2",
            lastPromptedVersion: "1.2"
        ))
        #expect(!ReviewPromptPolicy.shouldRequestReview(
            for: .quizCompleted(passed: true, currentStreakDays: 10),
            currentVersion: "1.2",
            lastPromptedVersion: "1.2"
        ))
    }

    @Test("declines when the app version is unknown/empty")
    func emptyVersionDeclines() {
        #expect(!ReviewPromptPolicy.shouldRequestReview(
            for: .bookFinished,
            currentVersion: "",
            lastPromptedVersion: nil
        ))
    }
}

// MARK: - Controller (side effects: request + persistence)

@MainActor
@Suite("ReviewPromptController")
struct ReviewPromptControllerTests {

    @Test("requests once at a qualifying moment and records the version")
    func requestsAndRecords() {
        let store = InMemoryReviewPromptVersionStore()
        let controller = ReviewPromptController(store: store, currentVersion: "2.0")
        var requestCount = 0

        let fired = controller.requestReviewIfAppropriate(
            for: .quizCompleted(passed: true, currentStreakDays: 5)
        ) { requestCount += 1 }

        #expect(fired)
        #expect(requestCount == 1)
        #expect(store.lastPromptedVersion() == "2.0")
    }

    @Test("does not request twice on the same version")
    func noSecondRequestSameVersion() {
        let store = InMemoryReviewPromptVersionStore()
        let controller = ReviewPromptController(store: store, currentVersion: "2.0")
        var requestCount = 0
        let request = { requestCount += 1 }

        _ = controller.requestReviewIfAppropriate(for: .bookFinished, performRequest: request)
        let secondFired = controller.requestReviewIfAppropriate(for: .bookFinished, performRequest: request)

        #expect(!secondFired)
        #expect(requestCount == 1)
    }

    @Test("never requests after a failure and leaves the store untouched")
    func neverRequestsAfterFailure() {
        let store = InMemoryReviewPromptVersionStore()
        let controller = ReviewPromptController(store: store, currentVersion: "2.0")
        var requestCount = 0

        let fired = controller.requestReviewIfAppropriate(
            for: .quizCompleted(passed: false, currentStreakDays: 30)
        ) { requestCount += 1 }

        #expect(!fired)
        #expect(requestCount == 0)
        #expect(store.lastPromptedVersion() == nil)
    }

    @Test("a new version re-enables a single prompt")
    func newVersionReenablesPrompt() {
        let store = InMemoryReviewPromptVersionStore(lastPromptedVersion: "1.0")
        let controller = ReviewPromptController(store: store, currentVersion: "2.0")
        var requestCount = 0

        let fired = controller.requestReviewIfAppropriate(
            for: .bookFinished
        ) { requestCount += 1 }

        #expect(fired)
        #expect(requestCount == 1)
        #expect(store.lastPromptedVersion() == "2.0")
    }
}
