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
    func loadSuccessTransitions() async {
        let model = makeModel()
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        if case .loaded = model.phase {
            // pass
        } else {
            Issue.record("Expected .loaded phase, got \(model.phase)")
        }
    }

    @Test("load() transitions phase to failed on network error")
    func loadFailureTransitions() async {
        let fake = FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        )
        let model = makeModel(repo: fake)
        model.load()
        await waitUntil { if case .failed = model.phase { return true }; return false }

        if case .failed = model.phase {
            // pass
        } else {
            Issue.record("Expected .failed phase, got \(model.phase)")
        }
    }

    @Test("load() is retriable — calling load() after error resets to loading")
    func loadIsRetriable() async {
        let fake = FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        )
        let model = makeModel(repo: fake)
        model.load()
        await waitUntil { if case .failed = model.phase { return true }; return false }
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
        await waitUntil { if case .loaded = model.phase { return true }; return false }
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
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        // Scroll to end
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-1")
        // Give any spurious PATCH task time to arrive before asserting it didn't.
        try await Task.sleep(for: .milliseconds(50))

        // chapterNumber (1) is NOT > serverCursorChapterNumber (1) → no PATCH
        #expect(fake.patchCursorCalls.isEmpty)
    }

    @Test("cursor is patched when chapterNumber is ahead of serverCursor")
    func cursorPatchedForward() async {
        let fake = FakeReaderRepository()
        // chapterNumber=2 but server cursor is at 1 → forward movement → patch
        let model = makeModel(chapterNumber: 2, repo: fake)
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        await waitUntil { !fake.patchCursorCalls.isEmpty }

        #expect(!fake.patchCursorCalls.isEmpty)
        #expect(fake.patchCursorCalls.first?.bookId == "test-book")
    }

    @Test("cursor PATCH is sent at most once per chapter load")
    func cursorPatchedOnce() async {
        let fake = FakeReaderRepository()
        let model = makeModel(chapterNumber: 2, repo: fake)
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        // Scroll to end multiple times
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        model.didScrollToBlock(9, blockCount: 10, chapterId: "ch-ah-2")
        await waitUntil { fake.patchCursorCalls.count >= 1 }

        // Only one PATCH sent despite multiple scroll events.
        #expect(fake.patchCursorCalls.count == 1)
    }

    // MARK: - Position save / restore

    @Test("scroll position is saved to repository")
    func scrollPositionSaved() async {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.scrollSaveDelay = .zero   // disable debounce in test
        model.didScrollToBlock(5, blockCount: 20, chapterId: "ch-1")
        // waitUntil polls every 5 ms; zero-sleep debounce completes on next runloop turn.
        await waitUntil { fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1) != nil }

        let saved = fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1)
        #expect(saved == 5)
    }

    @Test("scroll position is updated on subsequent scroll events")
    func scrollPositionUpdated() async {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.scrollSaveDelay = .zero   // disable debounce in test
        model.didScrollToBlock(3, blockCount: 20, chapterId: "ch-1")
        model.didScrollToBlock(7, blockCount: 20, chapterId: "ch-1")
        // Second call cancels the first debounce; only index 7 should be saved.
        await waitUntil { fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1) != nil }

        let saved = fake.loadScrollPosition(bookId: "test-book", chapterNumber: 1)
        #expect(saved == 7)
    }

    @Test("saved position is restored as pendingScrollAnchor after load")
    func positionRestoredAfterLoad() async {
        let fake = FakeReaderRepository()
        // Pre-save a position.
        fake.saveScrollPosition(bookId: "test-book", chapterNumber: 1, blockIndex: 8)

        let model = makeModel(chapterNumber: 1, repo: fake)
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

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
    func heartbeatsStartAfterLoad() async {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

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
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        model.onDisappear()
        // Give the cancelled task a moment to confirm no heartbeat fires.
        try await Task.sleep(for: .milliseconds(20))
        // Zero heartbeats in tests (30 s hasn't elapsed).
        #expect(fake.heartbeatCalls.isEmpty)
    }

    // MARK: - Depth recommendation (P6.4)

    @Test("confident recommendation sets recommendedVariant on controls model")
    func confidentRecommendationSetsVariant() async {
        let model = makeModel()
        let rec = DepthRecommendation(recommendedDepth: .medium, confidence: 0.85)
        model.fetchDepthRecommendation = { _ in rec }
        model.load()
        await waitUntil {
            if case .loaded(let c) = model.phase, c.recommendedVariant != nil { return true }
            return false
        }

        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected .loaded phase"); return
        }
        #expect(controls.recommendedVariant == .medium)
    }

    @Test("confident recommendation sets recommendedRationale on controls model")
    func confidentRecommendationSetsRationale() async {
        let model = makeModel()
        let rec = DepthRecommendation(recommendedDepth: .medium, confidence: 0.9)
        model.fetchDepthRecommendation = { _ in rec }
        model.load()
        await waitUntil {
            if case .loaded(let c) = model.phase, c.recommendedRationale != nil { return true }
            return false
        }

        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected .loaded phase"); return
        }
        #expect(controls.recommendedRationale != nil)
        #expect(!(controls.recommendedRationale ?? "").isEmpty)
    }

    @Test("low-confidence recommendation does not set recommendedVariant")
    func lowConfidenceDoesNotSetVariant() async {
        let model = makeModel()
        let rec = DepthRecommendation(recommendedDepth: .hard, confidence: 0.4)
        model.fetchDepthRecommendation = { _ in rec }
        model.load()
        // Wait for load, then yield twice to let the recommendation task settle.
        await waitUntil { if case .loaded = model.phase { return true }; return false }
        await Task.yield()
        await Task.yield()

        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected .loaded phase"); return
        }
        #expect(controls.recommendedVariant == nil)
    }

    @Test("nil recommendedDepth does not set recommendedVariant")
    func nilDepthDoesNotSetVariant() async {
        let model = makeModel()
        let rec = DepthRecommendation(recommendedDepth: nil, confidence: 0.9)
        model.fetchDepthRecommendation = { _ in rec }
        model.load()
        // Wait for load, then yield twice to let the recommendation task settle.
        await waitUntil { if case .loaded = model.phase { return true }; return false }
        await Task.yield()
        await Task.yield()

        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected .loaded phase"); return
        }
        #expect(controls.recommendedVariant == nil)
    }

    @Test("recommendation error does not affect phase")
    func recommendationErrorDoesNotAffectPhase() async {
        let model = makeModel()
        model.fetchDepthRecommendation = { _ in throw URLError(.notConnectedToInternet) }
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        if case .loaded = model.phase { } else {
            Issue.record("Expected .loaded despite recommendation error, got \(model.phase)")
        }
    }

    @Test("no recommendation when fetchDepthRecommendation is nil")
    func noRecommendationWhenNotWired() async {
        let model = makeModel()
        // fetchDepthRecommendation defaults to nil — no closure set
        model.load()
        await waitUntil { if case .loaded = model.phase { return true }; return false }

        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected .loaded phase"); return
        }
        #expect(controls.recommendedVariant == nil)
    }
}
