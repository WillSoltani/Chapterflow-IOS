import SwiftUI

/// The user's chosen appearance for the app.
public enum ThemeMode: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// A human-facing label (localized).
    public var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The `ColorScheme` to force, or `nil` to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public extension EnvironmentValues {
    /// The active ``ThemeMode``, readable by any descendant view.
    @Entry var themeMode: ThemeMode = .system
}

public extension View {
    /// Applies a ``ThemeMode`` to this view hierarchy: it publishes the mode in
    /// the environment *and* pins the color scheme accordingly.
    func themeMode(_ mode: ThemeMode) -> some View {
        environment(\.themeMode, mode)
            .preferredColorScheme(mode.colorScheme)
    }
}
