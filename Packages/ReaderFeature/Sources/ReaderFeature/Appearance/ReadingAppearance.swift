import SwiftUI
import Persistence

/// The resolved reading appearance: colors, font scale, and line spacing.
///
/// Propagated through the SwiftUI environment so every block view can read it
/// without prop-drilling. When `AppPreferences` changes, the host view updates
/// this value and SwiftUI redraws affected blocks immediately.
public struct ReadingAppearance: Sendable {
    /// Resolved color tokens for the current theme.
    public let colors: ReadingThemeTokens
    /// Font-size multiplier relative to the Dynamic Type body size.
    /// 1.0 == the DT preferred size; the block views clamp the result so it
    /// never drops below the DT floor (see `scaledBodySize(base:)`).
    public let fontScale: Double
    /// Extra inter-line spacing added to body text (points).
    public let lineSpacing: Double
    /// The resolved `ColorScheme` the host should apply to its window /
    /// container. `.nil` lets the system choose (for the `system` theme).
    public let colorSchemeOverride: ColorScheme?

    /// The default appearance — system theme, DT body size, comfortable spacing.
    public static let `default` = ReadingAppearance(
        colors: .systemTheme,
        fontScale: 1.0,
        lineSpacing: 6,
        colorSchemeOverride: nil
    )

    /// Creates an appearance from persisted user preferences.
    /// Must be called on the main actor because `AppPreferences` is `@MainActor`.
    @MainActor
    public init(preferences: AppPreferences) {
        let theme = preferences.readerTheme
        self.colors = .tokens(for: theme)
        self.fontScale = preferences.readerFontScale
        self.lineSpacing = preferences.readerLineSpacing
        switch theme {
        case .system: self.colorSchemeOverride = nil
        case .light, .sepia, .paper: self.colorSchemeOverride = .light
        case .dark: self.colorSchemeOverride = .dark
        }
    }

    /// Memberwise init for tests and previews.
    public init(
        colors: ReadingThemeTokens,
        fontScale: Double,
        lineSpacing: Double,
        colorSchemeOverride: ColorScheme?
    ) {
        self.colors = colors
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
        self.colorSchemeOverride = colorSchemeOverride
    }
}

// MARK: - Environment

private struct ReadingAppearanceKey: EnvironmentKey {
    static let defaultValue = ReadingAppearance.default
}

public extension EnvironmentValues {
    /// The current reading appearance; set by `ReaderContentView`.
    var readerAppearance: ReadingAppearance {
        get { self[ReadingAppearanceKey.self] }
        set { self[ReadingAppearanceKey.self] = newValue }
    }
}

// MARK: - View modifier

public extension View {
    /// Applies `appearance` to the environment and, when the theme is not
    /// `system`, overrides the color scheme so block views always see the
    /// right light/dark context.
    func readerAppearance(_ appearance: ReadingAppearance) -> some View {
        self
            .environment(\.readerAppearance, appearance)
            .applyColorScheme(appearance.colorSchemeOverride)
    }
}

private extension View {
    @ViewBuilder
    func applyColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.preferredColorScheme(scheme)
        } else {
            self
        }
    }
}
