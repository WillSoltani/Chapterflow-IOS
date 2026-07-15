import Foundation
import OSLog
import Persistence

private let ownerlessControlArtifactLog = Logger(
    subsystem: "com.chapterflow",
    category: "ownerless-app-group"
)

// MARK: - P8.9: Control Center controls

extension AppModel {

    /// Detects the pending navigation action written by P8.9 control intents
    /// (``StartReadingControlIntent``, ``StartReviewControlIntent``) via App Group UserDefaults.
    ///
    /// Legacy actions have no account owner. Preserve them without navigation
    /// until WP-ID-01B can attribute them safely.
    public func consumeControlIntentAction() {
        Self.preserveOwnerlessControlIntentAction(
            in: UserDefaults(suiteName: AppGroup.identifier)
        )
    }

    static func preserveOwnerlessControlIntentAction(in defaults: UserDefaults?) {
        guard defaults?.object(forKey: IntentKeys.controlPendingAction) != nil else {
            return
        }
        ownerlessControlArtifactLog.notice(
            "Ownerless navigation control action preserved for WP-ID-01B attribution"
        )
    }

    /// Preserves the legacy ownerless App Group playback state.
    ///
    /// Publishing account-private playback into an ownerless key could overwrite
    /// another account's state. WP-ID-01B must introduce ownership first.
    public func publishAudioPlayingState(_ isPlaying: Bool) {
        Self.preserveOwnerlessAudioPlayingState(
            isPlaying,
            in: UserDefaults(suiteName: AppGroup.identifier)
        )
    }

    static func preserveOwnerlessAudioPlayingState(
        _ proposedValue: Bool,
        in defaults: UserDefaults?
    ) {
        _ = proposedValue
        guard defaults?.object(forKey: IntentKeys.isAudioPlaying) != nil else {
            return
        }
        ownerlessControlArtifactLog.notice(
            "Ownerless audio playback state preserved for WP-ID-01B attribution"
        )
    }

    /// Detects accumulated reading minutes written by ``LogDailyReadingIntent``.
    ///
    /// The pending minutes have no account owner. Preserve them without crediting
    /// the current account until WP-ID-01B can attribute them safely.
    public func consumePendingReadingMinutes() {
        Self.preserveOwnerlessPendingReadingMinutes(
            in: UserDefaults(suiteName: AppGroup.identifier)
        )
    }

    static func preserveOwnerlessPendingReadingMinutes(in defaults: UserDefaults?) {
        guard defaults?.object(forKey: IntentKeys.pendingReadingMinutes) != nil else {
            return
        }
        ownerlessControlArtifactLog.notice(
            "Ownerless pending reading minutes preserved for WP-ID-01B attribution"
        )
    }
}
