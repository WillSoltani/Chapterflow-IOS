import Foundation
import Testing
@testable import AIFeature
import Models
import Persistence

@Suite("Audio session boundary", .serialized)
struct AudioSessionBoundaryTests {
    @Test("player reset is idempotent and clears account playback state")
    func playerResetIsIdempotent() async throws {
        let plan = AudioNarrationPlan.makeFake(
            bookId: "account-a-book",
            chapterNumber: 3,
            segmentDurations: [10, 20]
        )
        let player = AudioPlayer(repository: FakeAudioRepository(plan: plan))

        try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        await player.setSleepTimer(.minutes(5))
        await player.play()
        #expect(await player.hasAccountPlaybackStateForTest)

        await player.stopForSessionBoundary()
        await player.stopForSessionBoundary()

        let snapshot = await player.currentState
        #expect(snapshot.plan == nil)
        #expect(snapshot.globalTime == 0)
        #expect(snapshot.timeline.totalDuration == 0)
        #expect(snapshot.segmentIndex == 0)
        #expect(snapshot.isPlaying == false)
        #expect(await player.hasAccountPlaybackStateForTest == false)
        await #expect(throws: CancellationError.self) {
            try await player.loadChapter(bookId: "late-account-a-book", chapterNumber: 1)
        }
    }

    @Test("in-flight plan completion cannot repopulate a stopped player")
    func inFlightPlanCannotRepopulateStoppedPlayer() async {
        let plan = AudioNarrationPlan.makeFake(bookId: "account-a-book", chapterNumber: 4)
        let repository = BlockingAudioRepository(plan: plan)
        let player = AudioPlayer(repository: repository)
        let loadTask = Task {
            try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        }

        await repository.waitUntilFetchStarts()
        await player.stopForSessionBoundary()
        await repository.releaseFetch()

        await #expect(throws: CancellationError.self) {
            try await loadTask.value
        }
        #expect(await player.currentState.plan == nil)
        #expect(await player.hasAccountPlaybackStateForTest == false)
    }

    @Test("subscriber created after invalidation finishes immediately and is not retained")
    func lateSubscriberFinishesWithoutRetention() async {
        let player = AudioPlayer(repository: FakeAudioRepository())
        await player.stopForSessionBoundary()

        let updates = await player.updates()
        var iterator = updates.makeAsyncIterator()
        let update = await iterator.next()

        #expect(update == nil)
        #expect(await player.hasAccountPlaybackStateForTest == false)
    }

    @Test("model stop cancels retained work and clears all public account state")
    @MainActor
    func modelStopClearsStateAndWork() async {
        let suite = "AudioSessionBoundaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let plan = AudioNarrationPlan.makeFake(
            bookId: "account-a-book",
            chapterNumber: 2,
            segmentDurations: [10, 20]
        )
        let player = AudioPlayer(repository: FakeAudioRepository(plan: plan))
        let model = AudioPlayerModel(
            player: player,
            preferences: AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        )

        model.handle(.planLoaded(plan, AudioTimeline(durations: [10, 20])))
        model.handle(.timeUpdated(globalTime: 12, segmentIndex: 1))
        model.handle(.playingChanged(true))
        #expect(model.plan?.bookId == "account-a-book")
        #expect(model.hasRetainedSessionWorkForTest)

        await model.stopForSessionBoundary()
        await model.stopForSessionBoundary()
        model.handle(.planLoaded(plan, AudioTimeline(durations: [10, 20])))

        #expect(model.phase == .idle)
        #expect(model.plan == nil)
        #expect(model.currentGlobalTime == 0)
        #expect(model.timeline.totalDuration == 0)
        #expect(model.currentSegmentIndex == 0)
        #expect(model.isPlaying == false)
        #expect(model.sleepTimer == .off)
        #expect(model.isDownloaded == false)
        #expect(model.showMiniPlayer == false)
        #expect(model.hasRetainedSessionWorkForTest == false)
        #expect(await player.hasAccountPlaybackStateForTest == false)
    }

    @Test("reversible boundary invalidates a blocked fetch and detaches controls")
    @MainActor
    func reversibleBoundaryBlocksLatePlayback() async {
        let suite = "AudioSessionBoundaryTests.reversible.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let plan = AudioNarrationPlan.makeFake(bookId: "account-a-book", chapterNumber: 5)
        let repository = BlockingAudioRepository(plan: plan)
        let player = AudioPlayer(repository: repository)
        let model = AudioPlayerModel(
            player: player,
            preferences: AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        )

        let playTask = Task {
            await model.play(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        }
        await repository.waitUntilFetchStarts()

        let shouldResume = await model.pauseForSessionBoundary()
        #expect(shouldResume == false)
        #expect(model.hasRetainedSessionWorkForTest == false)

        await model.resumeAfterSessionBoundary(shouldResumePlayback: shouldResume)
        await repository.releaseFetch()
        await playTask.value

        #expect(model.plan == nil)
        #expect(model.isPlaying == false)
        #expect(await player.currentState.plan == nil)
        #expect(model.hasRetainedSessionWorkForTest)

        await model.stopForSessionBoundary()
    }

    @Test("final stop wins a blocked reversible resume without recreating work")
    @MainActor
    func finalStopWinsBlockedResume() async {
        let suite = "AudioSessionBoundaryTests.resumeStop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let player = AudioPlayer(repository: FakeAudioRepository())
        let model = AudioPlayerModel(
            player: player,
            preferences: AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        )
        _ = await model.pauseForSessionBoundary()

        let gate = ResumeActivationGate()
        model.beforeResumeActivationForTest = { await gate.block() }
        let resumeTask = Task {
            await model.resumeAfterSessionBoundary(shouldResumePlayback: true)
        }
        await gate.waitUntilStarted()

        await model.stopForSessionBoundary()
        await gate.release()
        await resumeTask.value
        model.beforeResumeActivationForTest = nil

        #expect(model.hasRetainedSessionWorkForTest == false)
        #expect(model.phase == .idle)
        #expect(model.plan == nil)
        #expect(model.isPlaying == false)
        #expect(await player.hasAccountPlaybackStateForTest == false)
    }

    @Test("reversible pause uses actor-authoritative playback intent")
    @MainActor
    func reversiblePauseUsesAuthoritativePlaybackIntent() async {
        let suite = "AudioSessionBoundaryTests.authority.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let player = AudioPlayer(repository: FakeAudioRepository())
        let model = AudioPlayerModel(
            player: player,
            preferences: AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        )

        // A stale optimistic model mirror must not cause an unexpected resume.
        model.handle(.playingChanged(true))
        let staleMirrorResult = await model.pauseForSessionBoundary()
        #expect(staleMirrorResult == false)
        await model.resumeAfterSessionBoundary(shouldResumePlayback: staleMirrorResult)
        #expect(await player.isPlaybackRequestedForTest == false)

        // Conversely, an actor-accepted play wins even before its stream update
        // reaches the model, and a failed sign-out resumes it exactly once.
        await player.play()
        let actualPlaybackResult = await model.pauseForSessionBoundary()
        #expect(actualPlaybackResult)
        #expect(await player.isPlaybackRequestedForTest == false)
        await model.resumeAfterSessionBoundary(shouldResumePlayback: actualPlaybackResult)
        #expect(await player.isPlaybackRequestedForTest)
        #expect(model.isPlaying)

        await model.stopForSessionBoundary()
    }
}

private actor ResumeActivationGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func block() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor BlockingAudioRepository: AudioRepository {
    private let plan: AudioNarrationPlan
    private var fetchStarted = false
    private var fetchStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchRelease: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    init(plan: AudioNarrationPlan) {
        self.plan = plan
    }

    func fetchPlan(bookId: String, chapterNumber: Int) async throws -> AudioNarrationPlan {
        fetchStarted = true
        let waiters = fetchStartWaiters
        fetchStartWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }

        if !wasReleased {
            await withCheckedContinuation { continuation in
                fetchRelease = continuation
            }
        }
        return plan
    }

    func waitUntilFetchStarts() async {
        if fetchStarted { return }
        await withCheckedContinuation { continuation in
            fetchStartWaiters.append(continuation)
        }
    }

    func releaseFetch() {
        wasReleased = true
        fetchRelease?.resume()
        fetchRelease = nil
    }

    func downloadSegment(
        remoteURL: URL,
        segmentId: String,
        to directory: URL
    ) async throws -> URL {
        directory.appending(path: "\(segmentId).mp3")
    }

    nonisolated func localURL(for segmentId: String, in directory: URL) -> URL? { nil }

    func postAudioSessionEvent(
        event: String,
        bookId: String,
        chapterNumber: Int,
        sessionId: String?,
        listeningSeconds: Double?
    ) async throws {}
}
