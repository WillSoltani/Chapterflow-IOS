/// Phase of the audio player presented to the UI.
public enum AudioPlayerPhase: Sendable, Equatable {
    case idle
    case loading
    case ready
    case recovering
    case error(String)
}
