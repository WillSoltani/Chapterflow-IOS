import Foundation
import OSLog
import Persistence

private let ownerlessAudioControlLog = Logger(
    subsystem: "com.chapterflow",
    category: "ownerless-app-group"
)

// MARK: - App Intent audio control

extension AppModel {

    /// Detects a pending audio control command written by P8.2 Live Activity buttons
    /// from legacy external surfaces via App Group UserDefaults.
    ///
    /// The legacy command has no account owner. WP-ID-01A therefore preserves it
    /// without applying it to the current audio player. WP-ID-01B must add durable
    /// ownership before these commands can be consumed safely.
    public func consumeAudioControlCommand() {
        Self.preserveOwnerlessAudioControlCommand(
            in: UserDefaults(suiteName: AppGroup.identifier)
        )
    }

    static func preserveOwnerlessAudioControlCommand(in defaults: UserDefaults?) {
        guard defaults?.object(forKey: IntentKeys.audioControlCommand) != nil else {
            return
        }
        ownerlessAudioControlLog.notice(
            "Ownerless audio control command preserved for WP-ID-01B attribution"
        )
    }
}
