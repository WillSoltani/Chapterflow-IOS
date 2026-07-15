/// Key namespace for App Intent ↔ AppModel communication via App Group UserDefaults.
enum IntentKeys {
    /// Accumulated offline reading minutes from ``LogDailyReadingIntent``.
    /// This legacy key has no owner; WP-ID-01A preserves it without crediting
    /// an account, and WP-ID-01B must add ownership before import.
    static let pendingReadingMinutes = "appIntent.pendingReadingMinutes"

    /// Legacy ownerless audio command preserved for WP-ID-01B migration.
    /// Values: `"play"`, `"pause"`. This legacy ownerless command is preserved
    /// without playback changes until WP-ID-01B adds ownership.
    static let audioControlCommand = "audioControlCommand"

    /// Pending navigation action written by P8.9 control intents.
    /// Values: `"startReading"`, `"startReview"`. This legacy ownerless action
    /// is preserved without routing until WP-ID-01B adds ownership.
    static let controlPendingAction = "controlIntent.pendingAction"

    /// Legacy ownerless audio-playing state. WP-ID-01A does not overwrite it
    /// with account-private playback; WP-ID-01B must introduce ownership.
    static let isAudioPlaying = "controlIntent.isAudioPlaying"
}
