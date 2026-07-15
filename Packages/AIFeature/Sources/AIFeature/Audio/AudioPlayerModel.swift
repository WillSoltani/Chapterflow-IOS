@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import SwiftUI
import Models
import Persistence

/// `@MainActor @Observable` model that drives the audio player UI.
///
/// Owns the ``AudioPlayer`` actor and translates its `AsyncStream` of
/// ``AudioPlaybackUpdate`` events into observable published properties.
/// Also manages:
/// - `AVAudioSession` category and interruption/route-change handling.
/// - `MPNowPlayingInfoCenter` (lock screen / Control Center metadata).
/// - `MPRemoteCommandCenter` (headphones, CarPlay, lock-screen transport).
/// - Sleep timer (delegates to ``AudioPlayer``).
/// - Auto-advance configuration.
/// - Session event posting for streak/reading-time.
@MainActor
@Observable
public final class AudioPlayerModel {

    // MARK: - Published state

    public private(set) var phase: AudioPlayerPhase = .idle
    public private(set) var currentGlobalTime: Double = 0
    public private(set) var timeline: AudioTimeline = .init(durations: [])
    public private(set) var currentSegmentIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var plan: AudioNarrationPlan?
    public private(set) var sleepTimer: SleepTimerOption = .off
    public private(set) var isDownloaded: Bool = false

    /// Playback speed mirrored from `AVQueuePlayer.rate` (set via ``setRate(_:)``).
    public private(set) var rate: Float = 1.0

    /// Whether this model's mini-player bar should be shown above the tab bar.
    public var showMiniPlayer: Bool { plan != nil && phase != .idle }

    // MARK: - Dependencies

    public let player: AudioPlayer
    private let preferences: AppPreferences
    private var offlineDirectory: URL?

    // MARK: - Session tracking

    private var sessionId: String?
    private var listeningStartTime: Double = 0
    private var sessionHeartbeatTask: Task<Void, Never>?
    private var playerUpdatesTask: Task<Void, Never>?
    private var audioSessionSetupTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var routeChangeTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var sessionEventTasks: [UUID: Task<Void, Never>] = [:]
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var lifecycleGeneration: UInt64 = 0
    private var isPausedForSessionBoundary = false
    private var isStoppedForSessionBoundary = false
    @ObservationIgnored
    var beforeResumeActivationForTest: (@MainActor @Sendable () async -> Void)?

    private var acceptsSessionWork: Bool {
        !isPausedForSessionBoundary && !isStoppedForSessionBoundary
    }

    // MARK: - Init

    public init(player: AudioPlayer, preferences: AppPreferences) {
        self.player = player
        self.preferences = preferences
        self.rate = Float(preferences.audioSpeed)
        audioSessionSetupTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, self.acceptsSessionWork else { return }
            self.setupAudioSession()
        }
        playerUpdatesTask = Task { [weak self] in
            await self?.observePlayerUpdates()
        }
        setupRemoteCommands()
        setupInterruptionObservers()
    }

    // MARK: - Public API

    /// Loads and plays a chapter's audio plan.
    /// - Parameters:
    ///   - bookId: The book identifier.
    ///   - chapterNumber: 1-based chapter number.
    ///   - offlineDirectory: Directory that holds downloaded segment files.
    ///   - startAt: Global chapter time to begin from (for position sync with reader).
    public func play(
        bookId: String,
        chapterNumber: Int,
        offlineDirectory: URL? = nil,
        startAt: Double = 0
    ) async {
        guard acceptsSessionWork else { return }
        let generation = lifecycleGeneration
        self.offlineDirectory = offlineDirectory
        phase = .loading
        sessionId = UUID().uuidString
        do {
            try await player.loadChapter(
                bookId: bookId,
                chapterNumber: chapterNumber,
                offlineDirectory: offlineDirectory,
                startAt: startAt
            )
            guard generation == lifecycleGeneration, acceptsSessionWork else {
                throw CancellationError()
            }
            await player.setRate(rate)
            guard generation == lifecycleGeneration, acceptsSessionWork else {
                throw CancellationError()
            }
            await player.play()
            guard generation == lifecycleGeneration, acceptsSessionWork else {
                throw CancellationError()
            }
            postSessionEvent("start", seconds: nil)
            startHeartbeat()
            prefetchTask?.cancel()
            prefetchTask = Task { [player] in await player.prefetchNextChapter() }
        } catch {
            if generation == lifecycleGeneration, acceptsSessionWork,
               !(error is CancellationError) {
                phase = .error(error.localizedDescription)
            }
        }
    }

    public func togglePlayPause() async {
        guard acceptsSessionWork else { return }
        if isPlaying {
            await player.pause()
            postSessionEvent("pause", seconds: currentGlobalTime - listeningStartTime)
        } else {
            await player.play()
            listeningStartTime = currentGlobalTime
            postSessionEvent("resume", seconds: nil)
        }
    }

    public func seek(to globalTime: Double) async {
        guard acceptsSessionWork else { return }
        await player.seek(to: globalTime)
    }

    public func skipForward() async {
        guard acceptsSessionWork else { return }
        await player.skipForward()
    }

    public func skipBackward() async {
        guard acceptsSessionWork else { return }
        await player.skipBackward()
    }

    public func setRate(_ newRate: Float) async {
        guard acceptsSessionWork else { return }
        rate = newRate
        preferences.audioSpeed = Double(newRate)
        await player.setRate(newRate)
    }

    public func setSleepTimer(_ option: SleepTimerOption) async {
        guard acceptsSessionWork else { return }
        sleepTimer = option
        await player.setSleepTimer(option)
    }

    /// Downloads all segments to `directory` for offline playback.
    public func downloadChapter(
        bookId: String,
        chapterNumber: Int,
        to directory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard acceptsSessionWork else { throw CancellationError() }
        let generation = lifecycleGeneration
        try await player.downloadChapter(
            bookId: bookId,
            chapterNumber: chapterNumber,
            to: directory,
            progress: progress
        )
        guard generation == lifecycleGeneration, acceptsSessionWork else {
            throw CancellationError()
        }
        isDownloaded = true
    }

    /// Reversibly quiesces all playback entry points and joins the retained
    /// account work owned by this model. The loaded plan remains isolated in
    /// this scope so a failed sign-out can resume it.
    @discardableResult
    public func pauseForSessionBoundary() async -> Bool {
        guard !isStoppedForSessionBoundary else { return false }
        guard !isPausedForSessionBoundary else { return false }

        lifecycleGeneration &+= 1
        isPausedForSessionBoundary = true
        stopHeartbeat()

        var tasks: [Task<Void, Never>] = []
        if let task = playerUpdatesTask { tasks.append(task) }
        if let task = audioSessionSetupTask { tasks.append(task) }
        if let task = interruptionTask { tasks.append(task) }
        if let task = routeChangeTask { tasks.append(task) }
        if let task = prefetchTask { tasks.append(task) }
        tasks.append(contentsOf: sessionEventTasks.values)
        tasks.forEach { $0.cancel() }

        playerUpdatesTask = nil
        audioSessionSetupTask = nil
        interruptionTask = nil
        routeChangeTask = nil
        prefetchTask = nil
        sessionEventTasks.removeAll(keepingCapacity: false)
        detachRemoteCommands()

        let shouldResumePlayback = await player.pauseForSessionBoundary()
        for task in tasks { await task.value }

        isPlaying = false
        updateNowPlayingPlayingState(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        return shouldResumePlayback
    }

    /// Restores the same isolated account scope after a cancelled sign-out.
    public func resumeAfterSessionBoundary(shouldResumePlayback: Bool) async {
        guard !isStoppedForSessionBoundary, isPausedForSessionBoundary else { return }

        let pausedGeneration = lifecycleGeneration
        await player.resumeAfterSessionBoundary()
        await beforeResumeActivationForTest?()
        guard pausedGeneration == lifecycleGeneration,
              !isStoppedForSessionBoundary,
              isPausedForSessionBoundary
        else { return }

        lifecycleGeneration &+= 1
        isPausedForSessionBoundary = false
        let resumedGeneration = lifecycleGeneration

        audioSessionSetupTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, self.acceptsSessionWork else { return }
            self.setupAudioSession()
        }
        playerUpdatesTask = Task { [weak self] in
            await self?.observePlayerUpdates()
        }
        setupRemoteCommands()
        setupInterruptionObservers()

        await player.setRate(rate)
        guard resumedGeneration == lifecycleGeneration, acceptsSessionWork else { return }
        await player.setSleepTimer(sleepTimer)
        guard resumedGeneration == lifecycleGeneration, acceptsSessionWork else { return }
        if let plan {
            updateNowPlaying(plan: plan, time: currentGlobalTime, timeline: timeline)
        }
        if shouldResumePlayback {
            await player.play()
            guard resumedGeneration == lifecycleGeneration, acceptsSessionWork else { return }
            isPlaying = true
            updateNowPlayingPlayingState(true)
            listeningStartTime = currentGlobalTime
            startHeartbeat()
        }
    }

    /// Irreversibly stops this account's playback work and clears all state
    /// that could otherwise remain visible after an account transition.
    ///
    /// A failed sign-out must use a reversible pause path instead. This method
    /// is reserved for a finalized session boundary and is safe to call more
    /// than once.
    public func stopForSessionBoundary() async {
        lifecycleGeneration &+= 1
        isPausedForSessionBoundary = true
        isStoppedForSessionBoundary = true

        var tasks: [Task<Void, Never>] = []
        if let task = sessionHeartbeatTask { tasks.append(task) }
        if let task = playerUpdatesTask { tasks.append(task) }
        if let task = audioSessionSetupTask { tasks.append(task) }
        if let task = interruptionTask { tasks.append(task) }
        if let task = routeChangeTask { tasks.append(task) }
        if let task = prefetchTask { tasks.append(task) }
        tasks.append(contentsOf: sessionEventTasks.values)
        tasks.forEach { $0.cancel() }

        sessionHeartbeatTask = nil
        playerUpdatesTask = nil
        audioSessionSetupTask = nil
        interruptionTask = nil
        routeChangeTask = nil
        prefetchTask = nil
        sessionEventTasks.removeAll(keepingCapacity: false)

        detachRemoteCommands()

        await player.stopForSessionBoundary()
        for task in tasks { await task.value }

        phase = .idle
        currentGlobalTime = 0
        timeline = .init(durations: [])
        currentSegmentIndex = 0
        isPlaying = false
        plan = nil
        sleepTimer = .off
        isDownloaded = false
        rate = 1.0
        offlineDirectory = nil
        sessionId = nil
        listeningStartTime = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }

    // MARK: - Observer loop

    private func observePlayerUpdates() async {
        for await update in await player.updates() {
            handle(update)
        }
    }

    func handle(_ update: AudioPlaybackUpdate) {
        guard acceptsSessionWork else { return }
        switch update {
        case .planLoaded(let newPlan, let newTimeline):
            plan = newPlan
            timeline = newTimeline
            phase = .ready
            updateNowPlaying(plan: newPlan, time: currentGlobalTime, timeline: newTimeline)

        case .timeUpdated(let globalTime, let segIdx):
            currentGlobalTime = globalTime
            currentSegmentIndex = segIdx
            updateNowPlayingTime(globalTime)

        case .playingChanged(let playing):
            isPlaying = playing
            updateNowPlayingPlayingState(playing)

        case .rateChanged(let r):
            rate = r

        case .segmentChanged(let idx):
            currentSegmentIndex = idx

        case .chapterEnded:
            isPlaying = false
            postSessionEvent("end", seconds: currentGlobalTime - listeningStartTime)
            stopHeartbeat()

        case .error(let msg):
            phase = .error(msg)
            isPlaying = false

        case .recovering:
            phase = .recovering
        }
    }

    // MARK: - Session heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        listeningStartTime = currentGlobalTime
        sessionHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, self.acceptsSessionWork else { break }
                let elapsed = self.currentGlobalTime - self.listeningStartTime
                self.postSessionEvent("heartbeat", seconds: elapsed)
                self.listeningStartTime = self.currentGlobalTime
            }
        }
    }

    private func stopHeartbeat() {
        sessionHeartbeatTask?.cancel()
        sessionHeartbeatTask = nil
    }

    private func postSessionEvent(_ event: String, seconds: Double?) {
        guard acceptsSessionWork else { return }
        let taskID = UUID()
        sessionEventTasks[taskID] = Task { @MainActor [weak self, player, sessionId] in
            await player.postListeningSession(
                event: event,
                sessionId: sessionId,
                listeningSeconds: seconds
            )
            self?.sessionEventTasks.removeValue(forKey: taskID)
        }
    }

    // MARK: - Interruption / route change

    private func setupInterruptionObservers() {
        #if canImport(UIKit)
        // Interruptions (phone calls etc.)
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let self, self.acceptsSessionWork else { break }
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { continue }

                if type == .began {
                    await self.player.pause()
                } else if type == .ended {
                    let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let opts = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if opts.contains(.shouldResume) {
                        await self.player.play()
                    }
                }
            }
        }

        // Route changes (headphones unplugged → pause)
        routeChangeTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard let self, self.acceptsSessionWork else { break }
                guard let info = notification.userInfo,
                      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else { continue }

                if reason == .oldDeviceUnavailable {
                    await self.player.pause()
                }
            }
        }
        #endif
    }

    // MARK: - MPNowPlayingInfoCenter

    private func updateNowPlaying(
        plan: AudioNarrationPlan,
        time: Double,
        timeline: AudioTimeline
    ) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = plan.chapterTitle ?? "Chapter \(plan.chapterNumber)"
        info[MPMediaItemPropertyAlbumTitle] = plan.bookTitle ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = timeline.totalDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)

        #if canImport(UIKit)
        if let artwork = makeArtworkImage(emoji: plan.coverEmoji, colorHex: plan.coverColor) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: CGSize(width: 600, height: 600)
            ) { _ in artwork }
        }
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime(_ time: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlayingState(_ playing: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(rate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - MPRemoteCommandCenter

    private func setupRemoteCommands() {
        guard acceptsSessionWork, remoteCommandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        let playTarget = center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.player.play()
            }
            return .success
        }
        remoteCommandTargets.append((center.playCommand, playTarget))

        let pauseTarget = center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.player.pause()
            }
            return .success
        }
        remoteCommandTargets.append((center.pauseCommand, pauseTarget))

        let toggleTarget = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.togglePlayPause()
            }
            return .success
        }
        remoteCommandTargets.append((center.togglePlayPauseCommand, toggleTarget))

        center.skipForwardCommand.preferredIntervals = [15]
        let skipForwardTarget = center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.skipForward()
            }
            return .success
        }
        remoteCommandTargets.append((center.skipForwardCommand, skipForwardTarget))

        center.skipBackwardCommand.preferredIntervals = [15]
        let skipBackwardTarget = center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.skipBackward()
            }
            return .success
        }
        remoteCommandTargets.append((center.skipBackwardCommand, skipBackwardTarget))

        let positionTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.seek(to: e.positionTime)
            }
            return .success
        }
        remoteCommandTargets.append((center.changePlaybackPositionCommand, positionTarget))

        center.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let rateTarget = center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                guard let self, self.acceptsSessionWork else { return }
                await self.setRate(Float(e.playbackRate))
            }
            return .success
        }
        remoteCommandTargets.append((center.changePlaybackRateCommand, rateTarget))
    }

    private func detachRemoteCommands() {
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.target)
        }
        remoteCommandTargets.removeAll(keepingCapacity: false)
    }

    /// Deterministic package-test evidence that every retained lifecycle task
    /// and command target has been detached.
    var hasRetainedSessionWorkForTest: Bool {
        sessionHeartbeatTask != nil || playerUpdatesTask != nil ||
            audioSessionSetupTask != nil || interruptionTask != nil ||
            routeChangeTask != nil || prefetchTask != nil ||
            !sessionEventTasks.isEmpty || !remoteCommandTargets.isEmpty
    }
}
