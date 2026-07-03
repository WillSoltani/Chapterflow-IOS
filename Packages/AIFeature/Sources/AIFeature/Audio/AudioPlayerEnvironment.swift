import SwiftUI

// MARK: - Environment key

private struct AudioPlayerModelKey: EnvironmentKey {
    static let defaultValue: AudioPlayerModel? = nil
}

public extension EnvironmentValues {
    /// The shared audio player model, injected from `AppFeature`'s composition root.
    ///
    /// Views that provide a "Listen" affordance read this via
    /// `@Environment(\.audioPlayerModel)`. `nil` in previews that don't inject it —
    /// hide audio controls gracefully when `nil`.
    var audioPlayerModel: AudioPlayerModel? {
        get { self[AudioPlayerModelKey.self] }
        set { self[AudioPlayerModelKey.self] = newValue }
    }
}
