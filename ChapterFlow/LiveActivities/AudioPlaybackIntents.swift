import AppIntents

// MARK: - AudioPlaybackIntents
//
// Compiled by BOTH the ChapterFlow app target AND the ChapterflowWidgets
// extension target. Buttons are no longer rendered, but the types remain so a
// cached Activity can fail closed without emitting an ownerless command.

/// Legacy cached pause action. It cannot prove the owning account.
public struct PauseAudioIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pause audio"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        return .result(
            dialog: "Audio can’t be controlled from this activity. Open ChapterFlow."
        )
    }
}

/// Legacy cached resume action. It cannot prove the owning account.
public struct ResumeAudioIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Resume audio"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        return .result(
            dialog: "Audio can’t be controlled from this activity. Open ChapterFlow."
        )
    }
}
