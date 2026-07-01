import Foundation
import Observation

/// User preferences that drive UI (theme, reading tone/depth, audio speed, …).
///
/// > Placeholder: the real `AppPreferences` lands with **Persistence (P0.4)**,
/// > backed by `UserDefaults` in the App Group so widgets share it. This local
/// > version stores everything in memory so the composition root can wire the
/// > theme end-to-end today. When P0.4 merges, delete this file and import the
/// > `Persistence` type instead — the surface (`themeMode`) is kept identical so
/// > call sites don't change.
@MainActor
@Observable
public final class AppPreferences {
    /// The user's selected appearance. Drives `preferredColorScheme` at the root.
    public var themeMode: ThemeMode

    public init(themeMode: ThemeMode = .system) {
        self.themeMode = themeMode
    }
}
