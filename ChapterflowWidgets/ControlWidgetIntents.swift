import AppIntents
import Foundation

// MARK: - ControlWidgetIntents
//
// App Intents that back the iOS 18 Control Center / Lock Screen / Action Button controls.
// These are compiled only in the ChapterflowWidgets extension target.
// Intents with openAppWhenRun = true signal AppModel via App Group; the main app
// routes on activation (consumeControlIntentAction). The audio toggle uses the
// existing audioControlCommand key already consumed by consumeAudioControlCommand().

private let cfAppGroupID = "group.com.chapterflow"

// MARK: - StartReadingControlIntent

/// "Start reading" control — opens ChapterFlow at the continue-reading chapter.
///
/// Writes `"startReading"` to `controlIntent.pendingAction` in the App Group.
/// `AppModel.consumeControlIntentAction()` reads this on scene activation and
/// routes to the correct chapter via `handle(deepLink:)`.
struct StartReadingControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Reading"
    static let description = IntentDescription(
        "Opens ChapterFlow at your current chapter.",
        categoryName: "Reading"
    )
    // The app opens; AppModel handles routing via the App Group signal.
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: cfAppGroupID)?
            .set("startReading", forKey: "controlIntent.pendingAction")
        return .result(dialog: "Opening your reading session.")
    }
}

// MARK: - StartReviewControlIntent

/// "Review now" control — opens ChapterFlow's spaced-repetition review session.
///
/// Writes `"startReview"` to `controlIntent.pendingAction` in the App Group.
struct StartReviewControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Now"
    static let description = IntentDescription(
        "Opens a spaced-repetition review session in ChapterFlow.",
        categoryName: "Reviews"
    )
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: cfAppGroupID)?
            .set("startReview", forKey: "controlIntent.pendingAction")
        return .result(dialog: "Opening your review session.")
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
    // Runs inline so the toggle flips without launching the app.
    static let openAppWhenRun = false

    @Parameter(title: "Is Playing")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: cfAppGroupID)
        // Reuses the key already observed by AppModel.consumeAudioControlCommand()
        defaults?.set(value ? "play" : "pause", forKey: "audioControlCommand")
        // Optimistic state for AudioPlaybackControl.Provider
        defaults?.set(value, forKey: "controlIntent.isAudioPlaying")
        return .result()
    }
}
