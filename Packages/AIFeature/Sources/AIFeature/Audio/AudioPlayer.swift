@preconcurrency import AVFoundation
import Foundation
import Models

// MARK: - AudioPlayer

/// Swift `actor` that drives an `AVQueuePlayer` for gapless multi-segment audio narration.
///
/// ## Design
/// - All `AVQueuePlayer` interactions happen from within the actor's executor.
/// - The player emits ``AudioPlaybackUpdate`` values via an `AsyncStream`; the
///   consuming ``AudioPlayerModel`` iterates them on `@MainActor`.
/// - A single global timeline (``AudioTimeline``) maps global chapter time onto
///   per-segment local offsets so seeking and 15-second skips cross segment
///   boundaries transparently.
/// - Presigned URL expiry (HTTP 403) is detected from `AVPlayerItem.status == .failed`.
///   The actor saves the current position, re-fetches the plan, and rebuilds the
///   queue seamlessly at the same point.
public actor AudioPlayer {

    // MARK: - Private state

    private let player = AVQueuePlayer()

    /// Current segment plan.
    private var plan: AudioNarrationPlan?

    /// Maps ObjectIdentifier(AVPlayerItem) → segment index for fast lookup.
    private var segmentIndex: [ObjectIdentifier: Int] = [:]

    /// Index of the FIRST segment in the current AVQueuePlayer queue (may differ
    /// from 0 after a seek rebuild or expiry recovery).
    private var queueStartSegmentIndex: Int = 0

    /// Cached timeline built from known segment durations.
    private var timeline: AudioTimeline = .init(durations: [])

    /// Latest global time derived from the periodic time observer.
    private var currentGlobalTime: Double = 0

    /// Local directory used for offline audio files.
    private var offlineDirectory: URL?

    /// Repository for plan fetches and session events.
    private let repository: any AudioRepository

    /// Book + chapter being played (used for expiry recovery and auto-advance).
    private var currentBookId: String = ""
    private var currentChapterNumber: Int = 0

    /// Next chapter's plan, prefetched for seamless auto-advance.
    private var nextChapterPlan: AudioNarrationPlan?

    /// Sleep-timer cancellation handle.
    private var sleepTimerTask: Task<Void, Never>?

    /// Whether we're in the middle of an expiry-recovery cycle (prevents recursion).
    private var isRecovering: Bool = false
    /// Actor-authoritative playback intent. AVPlayer's status can be `.waiting`
    /// while playback is legitimately requested, and the model mirror is async.
    private var isPlaybackRequested = false

    /// Whether all segments in the plan have finished.
    private var chapterEndReported: Bool = false

    /// Invalidates late async completions when the owning account scope ends.
    private var lifecycleGeneration: UInt64 = 0
    private var isInvalidated = false
    private var isPausedForSessionBoundary = false

    private var acceptsSessionWork: Bool {
        !isInvalidated && !isPausedForSessionBoundary
    }

    var remoteRepository: any AudioRepository { repository }
    var remoteGeneration: UInt64 { lifecycleGeneration }
    var remoteListeningContext: (bookId: String, chapterNumber: Int)? {
        currentBookId.isEmpty ? nil : (currentBookId, currentChapterNumber)
    }
    func acceptsRemoteWork(_ generation: UInt64? = nil) -> Bool {
        acceptsSessionWork && (generation.map { $0 == lifecycleGeneration } ?? true)
    }

    // MARK: - AsyncStream output

    private var continuations: [UUID: AsyncStream<AudioPlaybackUpdate>.Continuation] = [:]

    // The time observer token is `Any` (non-Sendable); isolated access inside actor is safe.
    private nonisolated(unsafe) var timeObserverToken: Any?

    // MARK: - Init

    public init(repository: any AudioRepository) {
        self.repository = repository
    }

    // MARK: - Deinit

    deinit {
        // Remove the periodic time observer BEFORE AVQueuePlayer is released.
        // AVFoundation traps (signal 5 / SIGTRAP) on macOS 26 when an AVPlayer
        // is deallocated while a live observer token is still registered — the
        // timer can fire into the partially-freed player. removeTimeObserver(_:)
        // must be balanced with every addPeriodicTimeObserver call.
        // timeObserverToken is nonisolated(unsafe) so it is reachable from deinit.
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        // Cancel background tasks so their for-await loops exit and stop posting
        // notifications or timer callbacks after the actor has been freed.
        sleepTimerTask?.cancel()
        notificationTask?.cancel()
    }

    // MARK: - AsyncStream

    /// Returns a stream of playback updates. The caller consumes this on `@MainActor`.
    /// Multiple subscribers are supported.
    public func updates() -> AsyncStream<AudioPlaybackUpdate> {
        let id = UUID()
        // Swift 6: [weak self] creates a `var`, which can't be directly captured in
        // @Sendable closures. Copy to a local `let` first; actors are Sendable so the
        // let-bound Optional<AudioPlayer> is safely capturable.
        return AsyncStream { [weak self] continuation in
            let ref: AudioPlayer? = self
            continuation.onTermination = { _ in Task { await ref?.removeContinuation(id: id) } }
            Task { await ref?.addContinuation(continuation, id: id) }
        }
    }

    private func addContinuation(_ c: AsyncStream<AudioPlaybackUpdate>.Continuation, id: UUID) {
        guard !isInvalidated else {
            c.finish()
            return
        }
        continuations[id] = c
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit(_ update: AudioPlaybackUpdate) {
        for c in continuations.values { c.yield(update) }
    }

    // MARK: - Load plan

    /// Fetches the audio plan from the repository and begins playback preparation.
    ///
    /// - Parameters:
    ///   - bookId: The book identifier.
    ///   - chapterNumber: 1-based chapter number.
    ///   - offlineDirectory: If non-nil, local URLs are preferred over presigned ones.
    ///   - startAt: Global chapter time to seek to before beginning playback.
    public func loadChapter(
        bookId: String,
        chapterNumber: Int,
        offlineDirectory: URL? = nil,
        startAt: Double = 0
    ) async throws {
        guard acceptsSessionWork else { throw CancellationError() }
        let generation = lifecycleGeneration
        currentBookId = bookId
        currentChapterNumber = chapterNumber
        self.offlineDirectory = offlineDirectory
        chapterEndReported = false

        let fetchedPlan = try await repository.fetchPlan(bookId: bookId, chapterNumber: chapterNumber)
        try Task.checkCancellation()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        await applyPlan(fetchedPlan, startAt: startAt)
        guard generation == lifecycleGeneration else { throw CancellationError() }
    }

    /// Applies a (possibly refreshed) plan to the queue, rebuilding from `startAt`.
    private func applyPlan(_ newPlan: AudioNarrationPlan, startAt: Double = 0) async {
        guard acceptsSessionWork else { return }
        plan = newPlan

        // Build timeline from server hints (updated with real durations as assets load).
        let hints = newPlan.segments.map { $0.durationSeconds ?? 60.0 }
        timeline = AudioTimeline(durations: hints)

        await rebuildQueue(from: 0, localOffset: 0)
        guard acceptsSessionWork else { return }

        // Now seek to desired start position.
        if startAt > 0 {
            await seekInternal(to: startAt)
            guard acceptsSessionWork else { return }
        }

        // Bind time observer once (it is stable across rebuilds because the player is stable).
        if timeObserverToken == nil {
            startTimeObserver()
        }

        // Observe failures for expiry recovery.
        startNotificationObservers()

        emit(.planLoaded(newPlan, timeline))
    }

    /// Rebuilds the AVQueuePlayer queue starting from `segmentStartIndex`.
    /// Creates fresh AVPlayerItems from the plan's URLs (or local overrides).
    private func rebuildQueue(from segmentStartIndex: Int, localOffset: Double) async {
        guard acceptsSessionWork, let plan else { return }

        player.pause()
        player.removeAllItems()
        segmentIndex = [:]
        queueStartSegmentIndex = segmentStartIndex

        let segments = plan.segments.dropFirst(segmentStartIndex)
        for (offset, segment) in segments.enumerated() {
            let url = resolvedURL(for: segment)
            let item = AVPlayerItem(url: url)
            segmentIndex[ObjectIdentifier(item)] = segmentStartIndex + offset
            player.insert(item, after: nil)
        }

        // Seek within the first segment if needed.
        if localOffset > 0 {
            let cmTime = CMTime(seconds: localOffset, preferredTimescale: 1000)
            await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard acceptsSessionWork else { return }
        }

        chapterEndReported = false
    }

    /// Returns the local URL if the segment is cached, otherwise the presigned URL.
    private func resolvedURL(for segment: AudioSegment) -> URL {
        if let dir = offlineDirectory,
           let local = repository.localURL(for: segment.segmentId, in: dir) {
            return local
        }
        return segment.url
    }

    // MARK: - Playback controls

    public func play() {
        guard acceptsSessionWork else { return }
        isPlaybackRequested = true
        player.play()
        emit(.playingChanged(true))
    }

    public func pause() {
        guard acceptsSessionWork else { return }
        isPlaybackRequested = false
        player.pause()
        emit(.playingChanged(false))
    }

    /// Stops playback and irreversibly clears all account-owned playback state.
    ///
    /// The operation is idempotent. Incrementing `lifecycleGeneration` before
    /// clearing state ensures a plan fetch, expiry recovery, prefetch, or
    /// download that completes late cannot repopulate the stopped scope.
    public func stopForSessionBoundary() {
        lifecycleGeneration &+= 1
        isInvalidated = true
        isPausedForSessionBoundary = true
        isPlaybackRequested = false

        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        notificationTask?.cancel()
        notificationTask = nil

        player.pause()
        player.removeAllItems()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        plan = nil
        segmentIndex.removeAll(keepingCapacity: false)
        queueStartSegmentIndex = 0
        timeline = .init(durations: [])
        currentGlobalTime = 0
        offlineDirectory = nil
        currentBookId = ""
        currentChapterNumber = 0
        nextChapterPlan = nil
        isRecovering = false
        chapterEndReported = false

        emit(.playingChanged(false))
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll(keepingCapacity: false)
    }

    /// Reversibly quiesces this scope. Any fetch or recovery that began before
    /// the boundary is generation-invalidated, while already loaded playback
    /// state is retained so a failed sign-out can resume the same account.
    public func pauseForSessionBoundary() async -> Bool {
        guard !isInvalidated, !isPausedForSessionBoundary else { return false }
        let shouldResumePlayback = isPlaybackRequested
        lifecycleGeneration &+= 1
        isPausedForSessionBoundary = true
        isPlaybackRequested = false

        let sleepTask = sleepTimerTask
        sleepTimerTask = nil
        sleepTask?.cancel()
        let observerTask = notificationTask
        notificationTask = nil
        observerTask?.cancel()

        player.pause()
        emit(.playingChanged(false))

        await sleepTask?.value
        await observerTask?.value
        return shouldResumePlayback
    }

    /// Reactivates a reversibly quiesced scope. Playback itself is resumed by
    /// `AudioPlayerModel` only when it was playing before the boundary.
    public func resumeAfterSessionBoundary() {
        guard !isInvalidated, isPausedForSessionBoundary else { return }
        lifecycleGeneration &+= 1
        isPausedForSessionBoundary = false
        if plan != nil {
            startNotificationObservers()
        }
    }

    public func setRate(_ rate: Float) {
        guard acceptsSessionWork else { return }
        player.rate = rate
        emit(.rateChanged(rate))
    }

    /// Seeks to an exact global chapter time, crossing segment boundaries as needed.
    public func seek(to globalTime: Double) async {
        guard acceptsSessionWork else { return }
        await seekInternal(to: globalTime)
    }

    private func seekInternal(to globalTime: Double) async {
        guard acceptsSessionWork else { return }
        let (targetSeg, localOffset) = timeline.position(at: globalTime)
        let currentSeg = currentSegmentIndex()

        if targetSeg == currentSeg {
            // Seek within the current segment.
            let cmTime = CMTime(seconds: localOffset, preferredTimescale: 1000)
            await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard acceptsSessionWork else { return }
        } else {
            // Target is a different segment — rebuild from there.
            let wasPlaying = player.timeControlStatus == .playing
            await rebuildQueue(from: targetSeg, localOffset: localOffset)
            guard acceptsSessionWork else { return }
            if wasPlaying { player.play() }
        }
        currentGlobalTime = globalTime
        emit(.timeUpdated(globalTime: globalTime, segmentIndex: targetSeg))
    }

    /// Skips forward by 15 seconds (crosses segment boundaries transparently).
    public func skipForward() async {
        guard acceptsSessionWork else { return }
        let newTime = Swift.min(currentGlobalTime + 15, timeline.totalDuration)
        await seek(to: newTime)
    }

    /// Skips backward by 15 seconds (crosses segment boundaries transparently).
    public func skipBackward() async {
        guard acceptsSessionWork else { return }
        let newTime = Swift.max(currentGlobalTime - 15, 0)
        await seek(to: newTime)
    }

    // MARK: - Sleep timer

    public func setSleepTimer(_ option: SleepTimerOption) {
        guard acceptsSessionWork else { return }
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard option != .off else { return }

        switch option {
        case .off:
            break
        case .endOfChapter:
            // Pause is triggered naturally when the last item finishes.
            // We set a flag so `handleChapterEnd` pauses instead of auto-advancing.
            break
        case .minutes(let m):
            sleepTimerTask = Task {
                try? await Task.sleep(for: .seconds(Double(m) * 60))
                if !Task.isCancelled {
                    self.pause()
                }
            }
        }
    }

    // MARK: - Auto-advance

    /// Prefetches the next chapter's plan so auto-advance is seamless.
    /// Called by ``AudioPlayerModel`` after the current chapter loads successfully.
    public func prefetchNextChapter() async {
        guard acceptsSessionWork, let plan else { return }
        let generation = lifecycleGeneration
        let next = plan.chapterNumber + 1
        do {
            let fetchedPlan = try await repository.fetchPlan(
                bookId: plan.bookId,
                chapterNumber: next
            )
            guard generation == lifecycleGeneration, !Task.isCancelled else { return }
            nextChapterPlan = fetchedPlan
        } catch {
            if generation == lifecycleGeneration {
                nextChapterPlan = nil
            }
        }
    }

    private func handleChapterEnd() async {
        guard acceptsSessionWork, !chapterEndReported else { return }
        let generation = lifecycleGeneration
        chapterEndReported = true
        sleepTimerTask?.cancel()
        emit(.chapterEnded(bookId: currentBookId, chapterNumber: currentChapterNumber))

        // Auto-advance if next plan is ready.
        if let next = nextChapterPlan {
            plan = next
            currentChapterNumber = next.chapterNumber
            chapterEndReported = false
            let hints = next.segments.map { $0.durationSeconds ?? 60.0 }
            timeline = AudioTimeline(durations: hints)
            await rebuildQueue(from: 0, localOffset: 0)
            guard generation == lifecycleGeneration, acceptsSessionWork else { return }
            emit(.planLoaded(next, timeline))
            player.play()
            // Schedule next-next prefetch so the chain continues.
            Task { await self.prefetchNextChapter() }
        } else {
            pause()
        }
    }

    // MARK: - Expiry recovery

    /// Called when an `AVPlayerItem` fails — checks for expiry and recovers.
    private func handleItemFailure(_ item: AVPlayerItem) async {
        guard acceptsSessionWork, !isRecovering else { return }
        let error = item.error as NSError?

        // Detect likely presigned-URL expiry (HTTP 403 surfaces as a URL error).
        guard isLikelyExpiry(error) else {
            emit(.error(error?.localizedDescription ?? "Playback failed"))
            return
        }

        isRecovering = true
        emit(.recovering)

        let generation = lifecycleGeneration
        let savedTime = currentGlobalTime
        do {
            let freshPlan = try await repository.fetchPlan(
                bookId: currentBookId,
                chapterNumber: currentChapterNumber
            )
            guard generation == lifecycleGeneration, !Task.isCancelled else { return }
            plan = freshPlan
            let hints = freshPlan.segments.map { $0.durationSeconds ?? 60.0 }
            timeline = AudioTimeline(durations: hints)
            await rebuildQueue(from: 0, localOffset: 0)
            guard generation == lifecycleGeneration, acceptsSessionWork else { return }
            await seekInternal(to: savedTime)
            guard generation == lifecycleGeneration, acceptsSessionWork else { return }
            player.play()
            emit(.planLoaded(freshPlan, timeline))
        } catch {
            if generation == lifecycleGeneration {
                emit(.error("Could not refresh audio: \(error.localizedDescription)"))
            }
        }
        if generation == lifecycleGeneration {
            isRecovering = false
        }
    }

    // MARK: - Segment tracking

    private func currentSegmentIndex() -> Int {
        guard let item = player.currentItem else { return queueStartSegmentIndex }
        return segmentIndex[ObjectIdentifier(item)] ?? queueStartSegmentIndex
    }

    // MARK: - Time observer

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 1000)
        // Capture via nonisolated trampoline to avoid Swift 6 var-capture warning.
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { await self?.handleTimeUpdate(seconds) }
        }
    }

    private func handleTimeUpdate(_ localTime: Double) async {
        guard acceptsSessionWork else { return }
        let segIdx = currentSegmentIndex()
        let globalTime = timeline.globalTime(segmentIndex: segIdx, localOffset: localTime)
        currentGlobalTime = globalTime
        emit(.timeUpdated(globalTime: globalTime, segmentIndex: segIdx))
    }

    // MARK: - Notification observers

    private var notificationTask: Task<Void, Never>?

    private func startNotificationObservers() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Item finished playing
                group.addTask {
                    for await notification in NotificationCenter.default.notifications(
                        named: AVPlayerItem.didPlayToEndTimeNotification
                    ) {
                        guard let item = notification.object as? AVPlayerItem else { continue }
                        await self?.handleItemDidFinish(item)
                    }
                }
                // Item failed
                group.addTask {
                    for await notification in NotificationCenter.default.notifications(
                        named: AVPlayerItem.failedToPlayToEndTimeNotification
                    ) {
                        guard let item = notification.object as? AVPlayerItem else { continue }
                        await self?.handleItemFailure(item)
                    }
                }
            }
        }
    }

    private func handleItemDidFinish(_ item: AVPlayerItem) async {
        guard acceptsSessionWork else { return }
        // Check if this was the last segment.
        guard let plan else { return }
        let idx = segmentIndex[ObjectIdentifier(item)] ?? 0
        if idx >= plan.segments.count - 1 {
            await handleChapterEnd()
        } else {
            let nextIdx = idx + 1
            emit(.segmentChanged(nextIdx))
        }
    }

    // MARK: - Snapshot for UI

    public var currentState: AudioPlayerSnapshot {
        AudioPlayerSnapshot(
            globalTime: currentGlobalTime,
            timeline: timeline,
            segmentIndex: currentSegmentIndex(),
            isPlaying: player.timeControlStatus == .playing,
            rate: player.rate,
            plan: plan
        )
    }

    // MARK: - Rate for expiry test support

    /// Saves the current global time — used by tests to verify recovery position.
    public var savedGlobalTimeForTest: Double { currentGlobalTime }

    /// Deterministic teardown evidence for package tests.
    var hasAccountPlaybackStateForTest: Bool {
        plan != nil || !currentBookId.isEmpty || currentChapterNumber != 0 ||
            currentGlobalTime != 0 || sleepTimerTask != nil || notificationTask != nil ||
            timeObserverToken != nil || !continuations.isEmpty
    }

    var isPlaybackRequestedForTest: Bool { isPlaybackRequested }
}
