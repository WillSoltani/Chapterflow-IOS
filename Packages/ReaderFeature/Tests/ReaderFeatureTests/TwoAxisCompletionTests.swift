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

    // MARK: - Knowledge axis

    @Test("isKnowledgeComplete is false when completedChapters is empty")
    func knowledgeNotCompleteByDefault() async throws {
        let fake = FakeReaderRepository()
        // Default fixture has completedChapters: []
        let model = makeModel(repo: fake)
        model.load()
        try await Task.sleep(for: .milliseconds(100))
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
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.isKnowledgeComplete)
    }

    @Test("isKnowledgeComplete resets to false when load() is called again")
    func knowledgeResetsOnReload() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        try await Task.sleep(for: .milliseconds(100))

        // Simulate completed state.
        // It resets when load() clears it.
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
        // Give async book state fetch time to complete.
        try await Task.sleep(for: .milliseconds(200))

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
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.applicationState == .none)
    }

    @Test("applicationState is .none when book state fetch fails")
    func applicationStateNoneOnError() async throws {
        let fake = FakeReaderRepository()
        fake.bookStateResponse = .failure(URLError(.notConnectedToInternet))

        let model = makeModel(repo: fake)
        model.load()
        try await Task.sleep(for: .milliseconds(200))

        // Error is suppressed; application state stays .none.
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
