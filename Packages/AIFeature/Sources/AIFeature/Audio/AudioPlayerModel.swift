import Foundation
import AVFoundation
import MediaPlayer
import Observation
import Models
import CoreKit

/// The observable model that owns and drives the chapter audio player.
///
/// A single, long-lived instance is created by `AppModel` and shared across
/// all tabs via the SwiftUI environment. Views must never create their own
/// instance.
///
/// Responsibilities:
/// - Load a signed chapter audio URL via ``AudioRepository``.
/// - Drive AVPlayer for play / pause / seek / skip / speed / sleep timer.
/// - Keep `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` in sync so
///   the lock screen and Control Center controls work.
/// - Render the book's emoji + color cover into Now Playing artwork.
@Observable
@MainActor
public final class AudioPlayerModel {

    // MARK: - Playback state (observed by views)

    /// The item currently loaded into the player, or `nil` when nothing is playing.
    public var currentItem: AudioPlaybackItem?

    /// `true` while audio is actively playing.
    public var isPlaying = false

    /// Elapsed playback position in seconds.
    public var currentTime: Double = 0

    /// Total duration of the current track in seconds. `1` until known (avoids ÷0).
    public var duration: Double = 1

    /// `true` while the audio URL is being fetched from the server.
    public var isLoading = false

    /// Non-`nil` when a load error occurred; `nil` when idle or playing normally.
    public var loadError: AppError?

    /// The playback speed multiplier (0.75–2.0).
    public var playbackRate: Float = 1.0

    /// When non-`nil`, the date/time at which the sleep timer will pause playback.
    public var sleepTimerEndDate: Date?

    // MARK: - Derived

    /// `true` when an item is loaded (playing or paused).
    public var hasActiveItem: Bool { currentItem != nil }

    /// Fractional playback progress in `[0, 1]`.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1)
    }

    // MARK: - Private

    private let repository: any AudioRepository
    private var player: AVPlayer?
    private var timeUpdateTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var endObserver: (any NSObjectProtocol)?

    // MARK: - Init

    public init(repository: any AudioRepository) {
        self.repository = repository
    }

    // MARK: - Load & play

    /// Fetches the audio URL for a chapter and begins playback.
    ///
    /// Safe to call from any view interaction handler; will cancel any
    /// in-flight load and replace the current item.
    public func loadAndPlay(_ request: AudioPlaybackRequest) async {
        isLoading = true
        loadError = nil
        do {
            let url = try await repository.chapterAudioURL(
                bookId: request.bookId,
                chapterNumber: request.chapterNumber
            )
            let item = AudioPlaybackItem(
                bookId: request.bookId,
                bookTitle: request.bookTitle,
                bookAuthor: request.bookAuthor,
                chapterNumber: request.chapterNumber,
                chapterTitle: request.chapterTitle,
                cover: request.cover,
                totalChapters: request.totalChapters,
                audioURL: url
            )
            startPlayback(item: item)
        } catch {
            loadError = error as? AppError ?? .offline
        }
        isLoading = false
    }

    // MARK: - Transport controls

    /// Toggles between play and pause.
    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = playbackRate
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    /// Seeks to an absolute position in seconds.
    public func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateNowPlayingInfo()
    }

    /// Skips forward (positive) or backward (negative) by `seconds`.
    public func skip(seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// Sets the playback rate; applies immediately when playing.
    public func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    // MARK: - Sleep timer

    /// Schedules a sleep timer.  Passing `nil` cancels an active timer.
    public func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes, minutes > 0 else {
            sleepTimerEndDate = nil
            return
        }
        let intervalSeconds = Double(minutes) * 60
        sleepTimerEndDate = Date.now.addingTimeInterval(intervalSeconds)
        sleepTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(intervalSeconds))
            guard !Task.isCancelled, let self else { return }
            self.player?.pause()
            self.isPlaying = false
            self.sleepTimerEndDate = nil
            self.updateNowPlayingInfo()
        }
    }

    // MARK: - System integration

    /// Activates the `AVAudioSession` for background playback.
    ///
    /// Call once from `AppModel.configure()` at app launch.
    public func activateAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            // Non-fatal: audio still works but won't play in the background.
        }
        #endif
    }

    /// Wires up `MPRemoteCommandCenter` so lock-screen and headphone controls work.
    ///
    /// Call once from `AppModel.configure()` at app launch.
    public func setupRemoteCommands() {
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                self.player?.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.player?.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(seconds: -15) }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(seconds: 15) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let evt = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor [weak self] in self?.seek(to: evt.positionTime) }
            }
            return .success
        }
        #endif
    }

    // MARK: - Private: start playback

    private func startPlayback(item: AudioPlaybackItem) {
        tearDown()

        currentItem = item
        currentTime = 0
        duration = 1

        let playerItem = AVPlayerItem(url: item.audioURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        player = avPlayer

        avPlayer.rate = playbackRate
        isPlaying = true

        startTimeTracking()
        observeItemEnd(playerItem: playerItem)
        updateNowPlayingInfo()
    }

    // MARK: - Private: time tracking

    private func startTimeTracking() {
        timeUpdateTask?.cancel()
        timeUpdateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { break }
                if let player = self.player {
                    let t = player.currentTime().seconds
                    if t.isFinite, t >= 0 { self.currentTime = t }
                    let dur = player.currentItem?.duration.seconds ?? 0
                    if dur.isFinite, dur > 0 { self.duration = dur }
                    // Mirror playing state to the AVPlayer rate (handles buffering stalls).
                    if self.isPlaying && player.rate == 0 && player.error == nil {
                        player.rate = self.playbackRate
                    }
                }
            }
        }
    }

    // MARK: - Private: end-of-track

    private func observeItemEnd(playerItem: AVPlayerItem) {
        if let existing = endObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = 0
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Private: Now Playing

    private func updateNowPlayingInfo() {
        #if os(iOS)
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.chapterTitle,
            MPMediaItemPropertyArtist: item.bookTitle,
            MPMediaItemPropertyAlbumTitle: item.bookAuthor,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: max(duration, 1),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let cover = item.cover, let image = renderedCoverImage(cover: cover) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: CGSize(width: 512, height: 512)
            ) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    // MARK: - Private: cover rendering

    #if os(iOS)
    private func renderedCoverImage(cover: Cover) -> UIImage? {
        let emoji = cover.emoji ?? "📖"
        let hexColor = cover.color ?? "#2D5BE3"

        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let fillColor = UIColor(hexString: hexColor) ?? .systemBlue
            fillColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 300)
            ]
            let emojiSize = (emoji as NSString).size(withAttributes: attrs)
            let origin = CGPoint(
                x: (size.width - emojiSize.width) / 2,
                y: (size.height - emojiSize.height) / 2
            )
            (emoji as NSString).draw(at: origin, withAttributes: attrs)
        }
    }
    #endif

    // MARK: - Private: teardown

    private func tearDown() {
        timeUpdateTask?.cancel()
        timeUpdateTask = nil
        sleepTask?.cancel()
        sleepTask = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }
}

// MARK: - UIColor hex helper

#if os(iOS)
private extension UIColor {
    /// Creates a `UIColor` from a CSS-style hex string (e.g. `"#3366CC"` or `"3366CC"`).
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
