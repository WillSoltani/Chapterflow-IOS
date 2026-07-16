import AppIntents

// MARK: - ControlWidgetIntents
//
// App Intents that back the iOS 18 Control Center / Lock Screen / Action Button controls.
// These are compiled only in the ChapterflowWidgets extension target.
// Intents with openAppWhenRun = true signal AppModel via App Group; the main app
// routes on activation (consumeControlIntentAction). The audio toggle uses the
// existing audioControlCommand key already consumed by consumeAudioControlCommand().

// MARK: - StartReadingControlIntent

/// "Start reading" control — opens ChapterFlow at the continue-reading chapter.
///
/// Cached legacy control. Account ownership is unavailable in the extension,
/// so it opens the app without emitting a cross-account routing command.
struct StartReadingControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Reading"
    static let description = IntentDescription(
        "Opens ChapterFlow so you can choose a book.",
        categoryName: "Reading"
    )
    // The app opens; AppModel handles routing via the App Group signal.
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        return .result(dialog: "Opening ChapterFlow. Choose a book to continue.")
    }
}

// MARK: - StartReviewControlIntent

/// "Review now" control — opens ChapterFlow's spaced-repetition review session.
///
/// Cached legacy control that opens the app without ownerless routing state.
struct StartReviewControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Now"
    static let description = IntentDescription(
        "Opens ChapterFlow so you can choose Reviews.",
        categoryName: "Reviews"
    )
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        return .result(dialog: "Opening ChapterFlow. Choose Reviews to continue.")
    }
}

// MARK: - ToggleAudioControlIntent

/// Audio play/pause toggle for the Control Center audio control.
///
/// Runs inline in the extension process (`openAppWhenRun = false`) and signals
/// the main app via the existing `audioControlCommand` App Group key, which
/// `AppModel.consumeAudioControlCommand()` processes on next foreground activation.
/// Also writes `controlIntent.isAudioPlaying` so the control's provider can
/// reflect the optimistic new state immediately.
struct ToggleAudioControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Audio Narration"
    static let description = IntentDescription(
        "Audio controls are unavailable until ChapterFlow can verify the active account.",
        categoryName: "Reading"
    )
    // Runs inline so the toggle flips without launching the app.
    static let openAppWhenRun = false

    @Parameter(title: "Is Playing")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        // Cached controls cannot prove which account owns the active player.
        // Preserve all legacy App Group values and make no playback mutation.
        return .result(
            dialog: "Audio can’t be controlled here yet. Open ChapterFlow to continue."
        )
    }
}
