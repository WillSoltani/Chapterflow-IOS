import AppIntents
import Foundation

// MARK: - AudioPlaybackIntents
//
// Compiled by BOTH the ChapterFlow app target AND the ChapterflowWidgets
// extension target. Lets Live Activity buttons invoke audio playback actions.
// P8.3 wires the perform() bodies; this file provides the shared types.

/// Pauses audio narration playback. Invoked from Dynamic Island buttons.
public struct PauseAudioIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pause audio"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        // P8.3 AudioIntents implementation will post a notification or use
        // the App Group to signal the AudioPlayerModel to pause.
        let appGroupID = "group.com.chapterflow"
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set("pause", forKey: "audioControlCommand")
        }
        return .result()
    }
}

/// Resumes audio narration playback. Invoked from Dynamic Island buttons.
public struct ResumeAudioIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Resume audio"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let appGroupID = "group.com.chapterflow"
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set("play", forKey: "audioControlCommand")
        }
        return .result()
    }
}
