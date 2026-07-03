@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import SwiftUI
import Models
import Persistence

/// Phase of the audio player presented to the UI.
public enum AudioPlayerPhase: Sendable, Equatable {
    case idle
    case loading
    case ready
    case recovering
    case error(String)
}

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

    // MARK: - Init

    public init(player: AudioPlayer, preferences: AppPreferences) {
        self.player = player
        self.preferences = preferences
        self.rate = Float(preferences.audioSpeed)
        Task { await self.setupAudioSession() }
        Task { await self.observePlayerUpdates() }
        Task { await self.setupRemoteCommands() }
        Task { await self.setupInterruptionObservers() }
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
            await player.setRate(rate)
            await player.play()
            postSessionEvent("start", seconds: nil)
            startHeartbeat()
            Task { await player.prefetchNextChapter() }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func togglePlayPause() async {
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
        await player.seek(to: globalTime)
    }

    public func skipForward() async { await player.skipForward() }
    public func skipBackward() async { await player.skipBackward() }

    public func setRate(_ newRate: Float) async {
        rate = newRate
        preferences.audioSpeed = Double(newRate)
        await player.setRate(newRate)
    }

    public func setSleepTimer(_ option: SleepTimerOption) async {
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
        try await player.downloadChapter(
            bookId: bookId,
            chapterNumber: chapterNumber,
            to: directory,
            progress: progress
        )
        isDownloaded = true
    }

    // MARK: - Observer loop

    private func observePlayerUpdates() async {
        for await update in await player.updates() {
            handle(update)
        }
    }

    private func handle(_ update: AudioPlaybackUpdate) {
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
                guard !Task.isCancelled else { break }
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
        Task {
            await player.postListeningSession(
                event: event,
                sessionId: sessionId,
                listeningSeconds: seconds
            )
        }
    }

    // MARK: - AVAudioSession

    private func setupAudioSession() async {
        #if canImport(UIKit)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: audio still works but won't respect background audio best practices.
        }
        #endif
    }

    // MARK: - Interruption / route change

    private func setupInterruptionObservers() async {
        #if canImport(UIKit)
        // Interruptions (phone calls etc.)
        Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { continue }

                if type == .began {
                    await player.pause()
                } else if type == .ended {
                    let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let opts = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if opts.contains(.shouldResume) {
                        await player.play()
                    }
                }
            }
        }

        // Route changes (headphones unplugged → pause)
        Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard let info = notification.userInfo,
                      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                else { continue }

                if reason == .oldDeviceUnavailable {
                    await player.pause()
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

    // MARK: - Artwork rendering

    #if canImport(UIKit)
    @MainActor
    private func makeArtworkImage(emoji: String?, colorHex: String?) -> UIImage? {
        let resolvedEmoji = emoji ?? "📚"
        let color = Color(hex: colorHex ?? "#3B82F6")
        let view = AudioArtworkView(emoji: resolvedEmoji, color: color)
            .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
    #endif

    // MARK: - MPRemoteCommandCenter

    private func setupRemoteCommands() async {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.player.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.player.pause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.skipForward() }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.skipBackward() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in await self.seek(to: e.positionTime) }
            return .success
        }

        center.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in await self.setRate(Float(e.playbackRate)) }
            return .success
        }
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
