import Foundation
import Persistence

// MARK: - App Intent audio control

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
}
