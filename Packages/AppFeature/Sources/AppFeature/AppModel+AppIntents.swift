import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
import CoreKit

// MARK: - App Intent integration

extension AppModel {

    /// Reads a pending audio control command written by P8.2 Live Activity buttons
    /// (``PauseAudioIntent`` / ``ResumeAudioIntent``) via App Group UserDefaults.
    ///
    /// Call when the app becomes active (scenePhase → `.active`) so commands from
    /// Dynamic Island taps are processed even after the app was backgrounded.
    public func consumeAudioControlCommand() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let command = defaults?.string(forKey: IntentKeys.audioControlCommand),
              !command.isEmpty else { return }
        defaults?.removeObject(forKey: IntentKeys.audioControlCommand)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch command {
            case "pause":
                if audioPlayerModel.isPlaying { await audioPlayerModel.togglePlayPause() }
            case "play":
                if !audioPlayerModel.isPlaying, audioPlayerModel.phase != .idle {
                    await audioPlayerModel.togglePlayPause()
                }
            default:
                break
            }
        }
    }

    /// Reads the pending navigation action written by P8.9 control intents
    /// (``StartReadingControlIntent``, ``StartReviewControlIntent``) via App Group UserDefaults.
    ///
    /// Call when the app becomes active (scenePhase → `.active`) so taps on
    /// Control Center / Lock Screen controls navigate to the right screen.
    public func consumeControlIntentAction() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let action = defaults?.string(forKey: IntentKeys.controlPendingAction),
              !action.isEmpty else { return }
        defaults?.removeObject(forKey: IntentKeys.controlPendingAction)
        switch action {
        case "startReading":
            let snapshot = SharedStateReader().load()
            if let bookId = snapshot.continueBookId, let chapter = snapshot.continueChapterNumber {
                handle(deepLink: .chapter(bookId: bookId, chapter: chapter))
            } else {
                handle(deepLink: .library)
            }
        case "startReview":
            handle(deepLink: .review)
        default:
            break
        }
    }

    /// Writes the current audio playing state to the App Group so the
    /// ``AudioPlaybackControl`` toggle reflects the live value.
    ///
    /// Call whenever `audioPlayerModel.isPlaying` changes.
    public func publishAudioPlayingState(_ isPlaying: Bool) {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        defaults?.set(isPlaying, forKey: IntentKeys.isAudioPlaying)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.chapterflow.ios.control.audio")
        #endif
    }

    /// Reads accumulated offline reading minutes written by ``LogDailyReadingIntent``,
    /// adds them to today's goal progress in the App Group snapshot, and publishes.
    ///
    /// Call when the app becomes active so the goal-ring widget reflects minutes
    /// logged via Siri since the last foreground session.
    public func consumePendingReadingMinutes() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let pending = defaults?.integer(forKey: IntentKeys.pendingReadingMinutes) ?? 0
        guard pending > 0 else { return }
        defaults?.removeObject(forKey: IntentKeys.pendingReadingMinutes)
        var updated = SharedStateReader().load()
        updated.goalProgressMinutes += pending
        updated.lastUpdated = Date()
        Task { await SharedStateWriter.shared.publish(updated) }
    }
}
