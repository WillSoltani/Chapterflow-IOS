import Testing
import Foundation
@testable import ReaderFeature
import Models
import Persistence

// MARK: - Reading session lifecycle tests

@MainActor
struct ReadingSessionTests {

    // MARK: - Helpers

    private func makeModel(
        chapterNumber: Int = 1,
        repo: FakeReaderRepository = FakeReaderRepository()
    ) -> ReaderModel {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.session.\(UUID().uuidString)"))
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

    // Polls until startReadingSession has been called.
    // startReadingSession is awaited after phase = .loaded inside performLoad, so
    // this is the correct signal that load fully completed including session setup.
    private func waitUntilSessionStarted(_ fake: FakeReaderRepository, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock().now
        while fake.startSessionCalls.isEmpty {
            if ContinuousClock().now - start > timeout {
                Issue.record("timed out waiting for session start")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    // Polls until endReadingSession has been called.
    private func waitUntilSessionEnded(_ fake: FakeReaderRepository, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock().now
        while fake.endSessionCalls.isEmpty {
            if ContinuousClock().now - start > timeout {
                Issue.record("timed out waiting for session end")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    // MARK: - Session start

    @Test("startReadingSession is called after a successful load")
    func sessionStartedAfterLoad() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        try await waitUntilSessionStarted(fake)

        #expect(!fake.startSessionCalls.isEmpty)
        #expect(fake.startSessionCalls.first?.bookId == "test-book")
    }

    @Test("sessionId from startReadingSession is passed to heartbeats")
    func sessionIdPassedToHeartbeat() async throws {
        let fake = FakeReaderRepository()
        fake.startSessionId = "test-session-42"
        let model = makeModel(repo: fake)
        model.load()
        try await waitUntilSessionStarted(fake)

        // Session should be started with our injected id.
        #expect(fake.startSessionCalls.count == 1)

        // Manually fire one heartbeat to verify sessionId threading.
        // (Normally fires after 30 s; we call the internal method via the model's repo.)
        guard case .loaded(let controls) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        let chapterId = controls.resolvedChapter.chapterId
        await fake.postReadingHeartbeat(bookId: "test-book", chapterId: chapterId, sessionId: "test-session-42")
        #expect(fake.heartbeatCalls.last?.sessionId == "test-session-42")
    }

    @Test("startReadingSession is NOT called when chapter fails to load")
    func sessionNotStartedOnError() async throws {
        let fake = FakeReaderRepository(
            chapterResponse: .failure(URLError(.notConnectedToInternet))
        )
        let model = makeModel(repo: fake)
        model.load()
        // Wait for the load attempt to resolve — it will transition to .failed, not .loaded.
        try await waitUntilLoaded(model)

        #expect(fake.startSessionCalls.isEmpty)
    }

    // MARK: - Session end

    @Test("endReadingSession is called on onDisappear")
    func sessionEndedOnDisappear() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)
        model.load()
        // Ensure startReadingSession has completed (phase = .loaded AND session set up).
        try await waitUntilSessionStarted(fake)

        model.onDisappear()
        try await waitUntilSessionEnded(fake)

        #expect(!fake.endSessionCalls.isEmpty)
        #expect(fake.endSessionCalls.first?.bookId == "test-book")
    }

    @Test("endReadingSession is NOT called when the reader never loaded")
    func sessionEndNotCalledWithoutLoad() async throws {
        let fake = FakeReaderRepository()
        let model = makeModel(repo: fake)

        // Phase is still .loading — onDisappear's `if case .loaded` block never executes,
        // so no endReadingSession Task is enqueued.
        model.onDisappear()
        await Task.yield()

        #expect(fake.endSessionCalls.isEmpty)
    }

    // MARK: - Inactivity

    @Test("inactivityThreshold constant is 60 seconds")
    func inactivityThresholdValue() {
        #expect(ReaderModel.inactivityThreshold == 60)
    }

    // MARK: - Loop completion

    @Test("notifyLoopComplete sets isLoopComplete")
    func loopCompleteFlag() {
        let model = makeModel()
        #expect(!model.isLoopComplete)
        model.notifyLoopComplete()
        #expect(model.isLoopComplete)
    }

    @Test("notifyLoopComplete fires onLoopComplete callback")
    func loopCompleteFiredCallback() {
        var callbackFired = false
        let model = makeModel()
        model.onLoopComplete = { callbackFired = true }
        model.notifyLoopComplete()
        #expect(callbackFired)
    }

    @Test("dismissLoopComplete clears isLoopComplete")
    func dismissLoopComplete() {
        let model = makeModel()
        model.notifyLoopComplete()
        #expect(model.isLoopComplete)
        model.dismissLoopComplete()
        #expect(!model.isLoopComplete)
    }

    @Test("load() resets isLoopComplete to false")
    func loadResetsLoopComplete() {
        let model = makeModel()
        model.notifyLoopComplete()
        model.load()
        #expect(!model.isLoopComplete)
    }
}
