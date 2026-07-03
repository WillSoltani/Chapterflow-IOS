import Testing
import Foundation
@testable import ReaderFeature
import Models
import Persistence

// MARK: - Two-axis completion display tests

@MainActor
struct TwoAxisCompletionTests {

    // MARK: - Helpers

    private func makeModel(
        chapterNumber: Int = 1,
        repo: FakeReaderRepository = FakeReaderRepository()
    ) -> ReaderModel {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.axis.\(UUID().uuidString)"))
        return ReaderModel(
            bookId: "test-book",
            chapterNumber: chapterNumber,
            variantFamily: .emh,
            repository: repo,
            preferences: prefs
        )
    }

    // Polls until model.phase exits .loading, or records a timeout failure.
    private func waitUntilLoaded(_ model: ReaderModel, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock().now
        while case .loading = model.phase {
            if ContinuousClock().now - start > timeout {
                Issue.record("timed out waiting for model to load")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    // Polls until the book-state fetch task has run (getBookState was called).
    // The book-state task fires after phase becomes .loaded, so this is needed
    // whenever a test asserts on applicationState remaining .none.
    private func waitUntilBookStateFetched(_ fake: FakeReaderRepository, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock().now
        while fake.getBookStateCalls == 0 {
            if ContinuousClock().now - start > timeout {
                Issue.record("timed out waiting for book-state fetch")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    // Polls until applicationState leaves .none — used when a test expects a non-default value.
    private func waitUntilApplicationStateSet(_ model: ReaderModel, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock().now
        while model.applicationState == .none {
            if ContinuousClock().now - start > timeout {
                Issue.record("timed out waiting for applicationState to be set")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    // MARK: - Knowledge axis

    @Test("isKnowledgeComplete is false when completedChapters is empty")
    func knowledgeNotCompleteByDefault() async throws {
        let fake = FakeReaderRepository()
        // Default fixture has completedChapters: []
        let model = makeModel(repo: fake)
        model.load()
        try await waitUntilLoaded(model)
        #expect(!model.isKnowledgeComplete)
    }

    @Test("isKnowledgeComplete is true when chapterNumber appears in completedChapters")
    func knowledgeCompleteWhenInProgress() async throws {
        let fake = FakeReaderRepository()
        // Patch the fixture to include chapter 1 as completed.
        let json = """
        {
            "chapter": {
                "chapterId": "ch-test-1",
                "number": 1,
                "title": "Test Chapter",
                "readingTimeMinutes": 5,
                "activeVariant": "medium",
                "availableVariants": ["medium"],
                "content": {
                    "chapterBreakdown": {
                        "gentle": "Test.",
                        "direct": "Test.",
                        "competitive": "Test."
                    },
                    "keyTakeaways": []
                },
                "contentVariants": {},
                "examples": []
            },
            "progress": {
                "currentChapterNumber": 2,
                "unlockedThroughChapterNumber": 2,
                "completedChapters": [1],
                "bestScoreByChapter": {"1": 90},
                "preferredVariant": null,
                "progressRev": 2
            }
        }
        """
        // swiftlint:disable:next force_try
        let response = try! JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: Data(json.utf8))
        fake.chapterResponse = .success(response)

        let model = makeModel(chapterNumber: 1, repo: fake)
        model.load()
        // isKnowledgeComplete is set before phase transitions to .loaded, so
        // waiting for load to complete is sufficient.
        try await waitUntilLoaded(model)

        #expect(model.isKnowledgeComplete)
    }

    @Test("isKnowledgeComplete resets to false when load() is called again")
    func knowledgeResetsOnReload() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        try await waitUntilLoaded(model)

        // load() synchronously resets isKnowledgeComplete before spawning the new task.
        model.load()
        #expect(!model.isKnowledgeComplete)
    }

    // MARK: - Application axis

    @Test("applicationState defaults to .none before book state loads")
    func applicationStateDefaultsToNone() {
        let model = makeModel()
        #expect(model.applicationState == .none)
    }

    @Test("applicationState is populated from book state after load")
    func applicationStatePopulated() async throws {
        let fake = FakeReaderRepository()
        fake.bookStateResponse = .success(BookStateResponse(
            state: BookUserBookState(
                currentChapterId: "ch-ah-1",
                completedChapterIds: [],
                unlockedChapterIds: ["ch-ah-1"],
                chapterScores: [:],
                chapterCompletedAt: [:],
                lastReadChapterId: nil,
                lastOpenedAt: nil
            ),
            applicationStates: ["ch-ah-1": .committed]
        ))

        let model = makeModel(repo: fake)
        model.load()
        // Poll until the book-state task resolves to a non-.none value.
        try await waitUntilApplicationStateSet(model)

        #expect(model.applicationState == .committed)
    }

    @Test("applicationState is .none when chapter has no entry in applicationStates")
    func applicationStateNoneWhenMissing() async throws {
        let fake = FakeReaderRepository()
        fake.bookStateResponse = .success(BookStateResponse(
            state: BookUserBookState(
                currentChapterId: "ch-ah-1",
                completedChapterIds: [],
                unlockedChapterIds: ["ch-ah-1"],
                chapterScores: [:],
                chapterCompletedAt: [:],
                lastReadChapterId: nil,
                lastOpenedAt: nil
            ),
            applicationStates: [:]  // Empty — this chapter has no state yet.
        ))

        let model = makeModel(repo: fake)
        model.load()
        // Wait until getBookState has been called so the task has run to completion.
        // The result stays .none because the chapter key is absent.
        try await waitUntilBookStateFetched(fake)

        #expect(model.applicationState == .none)
    }

    @Test("applicationState is .none when book state fetch fails")
    func applicationStateNoneOnError() async throws {
        let fake = FakeReaderRepository()
        fake.bookStateResponse = .failure(URLError(.notConnectedToInternet))

        let model = makeModel(repo: fake)
        model.load()
        // Wait until getBookState has been attempted (error is swallowed; state stays .none).
        try await waitUntilBookStateFetched(fake)

        #expect(model.applicationState == .none)
    }

    @Test("unknown application state decodes without crashing")
    func unknownApplicationStateToleranced() {
        let raw = "future_state_from_server"
        let state = ChapterApplicationState(rawValue: raw)
        if case .unknown(let s) = state {
            #expect(s == raw)
        } else {
            Issue.record("Expected .unknown for unrecognised rawValue")
        }
    }

    // MARK: - ChapterApplicationState evolution contract

    @Test("all known application states round-trip through rawValue")
    func applicationStateRawValueRoundTrip() {
        let cases: [ChapterApplicationState] = [.none, .committed, .applied]
        for c in cases {
            let roundTripped = ChapterApplicationState(rawValue: c.rawValue)
            #expect(roundTripped == c)
        }
    }
}
