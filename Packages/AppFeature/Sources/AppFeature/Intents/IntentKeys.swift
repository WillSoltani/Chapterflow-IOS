/// Key namespace for App Intent ↔ AppModel communication via App Group UserDefaults.
enum IntentKeys {
    /// Accumulated offline reading minutes from ``LogDailyReadingIntent``.
    /// The main app adds these to today's goal progress on next activation.
    static let pendingReadingMinutes = "appIntent.pendingReadingMinutes"

    /// Audio control command written by P8.2 Live Activity buttons (``PauseAudioIntent`` /
    /// ``ResumeAudioIntent``) and by ``ToggleAudioControlIntent`` (P8.9 controls).
    /// Values: `"play"`, `"pause"`. Cleared after consumption.
    static let audioControlCommand = "audioControlCommand"

    /// Pending navigation action written by P8.9 control intents.
    /// Values: `"startReading"`, `"startReview"`. Cleared after consumption.
    static let controlPendingAction = "controlIntent.pendingAction"

    /// Current audio playing state written by AppModel so the P8.9 audio control
    /// toggle reflects the live state. `true` when audio is playing.
    static let isAudioPlaying = "controlIntent.isAudioPlaying"
}
