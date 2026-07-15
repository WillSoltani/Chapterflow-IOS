import Foundation
import Models

/// Point-in-time snapshot of ``AudioPlayer`` state for UI hydration.
public struct AudioPlayerSnapshot: Sendable {
    public let globalTime: Double
    public let timeline: AudioTimeline
    public let segmentIndex: Int
    public let isPlaying: Bool
    public let rate: Float
    public let plan: AudioNarrationPlan?
}

/// Playback phase broadcast by ``AudioPlayer`` via its `AsyncStream`.
public enum AudioPlaybackUpdate: Sendable {
    case planLoaded(AudioNarrationPlan, AudioTimeline)
    case timeUpdated(globalTime: Double, segmentIndex: Int)
    case playingChanged(Bool)
    case rateChanged(Float)
    case segmentChanged(Int)
    case chapterEnded(bookId: String, chapterNumber: Int)
    case error(String)
    case recovering
}

/// Sleep-timer option presented in the UI and stored in ``AudioPlayerModel``.
public enum SleepTimerOption: Sendable, Equatable, CaseIterable, Hashable {
    case off
    case endOfChapter
    case minutes(Int)

    public static let allCases: [SleepTimerOption] = [
        .off, .endOfChapter,
        .minutes(5), .minutes(10), .minutes(15), .minutes(20),
        .minutes(30), .minutes(45), .minutes(60)
    ]

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .endOfChapter: return "End of chapter"
        case .minutes(let minutes): return "\(minutes) min"
        }
    }
}
