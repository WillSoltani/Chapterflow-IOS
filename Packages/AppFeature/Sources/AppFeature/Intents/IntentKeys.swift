/// Key namespace for App Intent ↔ AppModel communication via App Group UserDefaults.
enum IntentKeys {
    /// Accumulated offline reading minutes from ``LogDailyReadingIntent``.
    /// The main app adds these to today's goal progress on next activation.
    static let pendingReadingMinutes = "appIntent.pendingReadingMinutes"

    /// Audio control command written by P8.2 Live Activity buttons (``PauseAudioIntent`` /
    /// ``ResumeAudioIntent``). Values: `"play"`, `"pause"`. Cleared after consumption.
    static let audioControlCommand = "audioControlCommand"
}
