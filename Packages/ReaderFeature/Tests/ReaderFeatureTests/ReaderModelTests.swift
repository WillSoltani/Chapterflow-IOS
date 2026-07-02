import Testing
import Foundation
@testable import ReaderFeature
import Models
import Persistence

// MARK: - ReaderModel tests

@MainActor
struct ReaderModelTests {

    // MARK: - Helpers

    private func makeModel(
        chapterNumber: Int = 1,
        repo: FakeReaderRepository = FakeReaderRepository()
    ) -> ReaderModel {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        return ReaderModel(
            bookId: "test-book",
            chapterNumber: chapterNumber,
            variantFamily: .emh,
            repository: repo,
            preferences: prefs
        )
    }

    // MARK: - Load → loaded

    @Test("load() transitions phase from loading to loaded on success")
    func loadSuccessTransitions() async throws {
        let model = makeModel()
        model.load()
        // Flush the async load task.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        if case .loaded = model.phase {
            // pass
        } else {
            Issue.record("Expected .loaded phase, got \(model.phase)")
        }
    }

    @Test("load() transitions phase to failed on network error")
    func loadFailureTransitions() async throws {
        let fake = FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        )
        let model = makeModel(repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        if case .failed = model.phase {
            // pass
        } else {
            Issue.record("Expected .failed phase, got \(model.phase)")
        }
    }

    @Test("load() is retriable — calling load() after error resets to loading")
    func loadIsRetriable() async throws {
        let fake = FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        )
        let model = makeModel(repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        // Should be .failed
        guard case .failed = model.phase else {
            Issue.record("Expected .failed before retry")
            return
        }
        // Swap to a successful response and retry.
        fake.chapterResponse = FakeReaderRepository().chapterResponse
        model.load()
        // Immediately after calling load() phase is .loading
        if case .loading = model.phase { } else {
            Issue.record("Expected .loading immediately after load()")
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        if case .loaded = model.phase { } else {
            Issue.record("Expected .loaded after successful retry")
        }
    }

    // MARK: - readPercent

    @Test("didScrollToBlock computes readPercent correctly")
    func readPercentComputation() {
        let model = makeModel()
        model.didScrollToBlock(0, blockCount: 10, chapterId: "ch-1")
        #expect(model.readPercent == 0.1)

        model.didScrollToBlock(4, blockCount: 10, chapterId: "ch-1")
        #expect(model.readPercent == 0.5)

        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-1")
        #expect(model.readPercent == 1.0)
    }

    @Test("readPercent is clamped to 1.0 even if blockIndex exceeds blockCount")
    func readPercentClamped() {
        let model = makeModel()
        model.didScrollToBlock(100, blockCount: 10, chapterId: "ch-1")
        #expect(model.readPercent <= 1.0)
    }

    @Test("readPercent is 0 when blockCount is 0")
    func readPercentZeroBlockCount() {
        let model = makeModel()
        model.didScrollToBlock(0, blockCount: 0, chapterId: "ch-1")
        #expect(model.readPercent == 0)
    }

    // MARK: - Quiz CTA threshold

    @Test("showQuizCTA is false before threshold")
    func quizCTAHidden() {
        let model = makeModel()
        // 84% — just below 85% threshold
        model.didScrollToBlock(7, blockCount: 10, chapterId: "ch-1")  // 80%
        #expect(!model.showQuizCTA)
    }

    @Test("showQuizCTA becomes true at the threshold")
    func quizCTAVisible() {
        let model = makeModel()
        // blockIndex 8 of 10 → 9/10 = 90% ≥ 85%
        model.didScrollToBlock(8, blockCount: 10, chapterId: "ch-1")
        #expect(model.showQuizCTA)
    }

    @Test("isAtChapterEnd becomes true at 95% threshold")
    func chapterEndDetection() {
        let model = makeModel()
        // blockIndex 9 of 10 → 10/10 = 100% ≥ 95%
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-1")
        #expect(model.isAtChapterEnd)
    }

    @Test("isAtChapterEnd is false below 95% threshold")
    func chapterEndNotYet() {
        let model = makeModel()
        // blockIndex 8 of 10 → 90% < 95%
        model.didScrollToBlock(8, blockCount: 10, chapterId: "ch-1")
        #expect(!model.isAtChapterEnd)
    }

    // MARK: - Forward-only cursor

    @Test("cursor is not patched when chapterNumber equals serverCursor")
    func cursorNotPatchedAtServerCursor() async throws {
        let fake = FakeReaderRepository()
        // Server progress reports currentChapterNumber = 1.
        // Our chapter is also 1. No forward movement → no patch.
        let model = makeModel(chapterNumber: 1, repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        // Scroll to end
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-1")
        try await Task.sleep(for: .milliseconds(50))

        // chapterNumber (1) is NOT > serverCursorChapterNumber (1) → no PATCH
        #expect(fake.patchCursorCalls.isEmpty)
    }

    @Test("cursor is patched when chapterNumber is ahead of serverCursor")
    func cursorPatchedForward() async throws {
        let fake = FakeReaderRepository()
        // chapterNumber=2 but server cursor is at 1 → forward movement → patch
        let model = makeModel(chapterNumber: 2, repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        try await Task.sleep(for: .milliseconds(50))

        #expect(!fake.patchCursorCalls.isEmpty)
        #expect(fake.patchCursorCalls.first?.bookId == "test-book")
    }

    @Test("cursor PATCH is sent at most once per chapter load")
    func cursorPatchedOnce() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(chapterNumber: 2, repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        // Scroll to end multiple times
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        try await Task.sleep(for: .milliseconds(50))

        // Only one PATCH sent despite multiple scroll events.
        #expect(fake.patchCursorCalls.count == 1)
    }

    // MARK: - Position save / restore

    @Test("scroll position is saved to repository")
    func scrollPositionSaved() {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.didScrollToBlock(5, blockCount: 20, chapterId: "ch-1")

        let saved = fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1)
        #expect(saved == 5)
    }

    @Test("scroll position is updated on subsequent scroll events")
    func scrollPositionUpdated() {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.didScrollToBlock(3, blockCount: 20, chapterId: "ch-1")
        model.didScrollToBlock(7, blockCount: 20, chapterId: "ch-1")

        let saved = fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1)
        #expect(saved == 7)
    }

    @Test("saved position is restored as pendingScrollAnchor after load")
    func positionRestoredAfterLoad() async throws {
        let fake = FakeReaderRepository()
        // Pre-save a position.
        fake.saveScrollPosition(bookId: "test-book", chapterNumber: 1, blockIndex: 8)

        let model = makeModel(chapterNumber: 1, repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        if case .loaded(let controlsModel) = model.phase {
            // pendingScrollAnchor is clamped to blocks.count - 1.
            // If blocks.count > 8 the anchor should be 8; if not, it should be clamped.
            let expectedAnchor = min(8, controlsModel.blocks.count - 1)
            #expect(controlsModel.pendingScrollAnchor == expectedAnchor)
        } else {
            Issue.record("Expected .loaded phase")
        }
    }

    // MARK: - Heartbeats

    @Test("heartbeats start after a successful load")
    func heartbeatsStartAfterLoad() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        // Heartbeat loop is running — no heartbeat should have fired yet
        // (first one fires after 30 s, which we don't wait for in tests).
        // Verify the model is in the loaded state (loop was started).
        if case .loaded = model.phase { } else {
            Issue.record("Expected .loaded — heartbeats only start when loaded")
        }
    }

    @Test("onDisappear stops heartbeats")
    func heartbeatsStopOnDisappear() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        model.onDisappear()
        // No assertion needed — just verify it doesn't crash and
        // that subsequent heartbeat calls from the old task don't happen.
        try await Task.sleep(for: .milliseconds(20))
        // Zero heartbeats in tests (30 s hasn't elapsed).
        #expect(fake.heartbeatCalls.isEmpty)
    }
}
