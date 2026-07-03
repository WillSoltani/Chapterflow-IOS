import Foundation
import Models

public extension Fixtures {

    // MARK: - Audio narration

    /// A pre-decoded audio narration plan for Atomic Habits ch.1.
    static let audioPlan: AudioNarrationPlan = {
        let response: AudioNarrationResponse = load("audio_plan")
        return response.plan
    }()
}
