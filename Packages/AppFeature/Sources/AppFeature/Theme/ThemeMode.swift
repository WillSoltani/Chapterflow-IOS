import SwiftUI

/// The user's appearance preference.
///
/// > Placeholder: **DesignSystem (P0.2)** ships the canonical `ThemeMode` (plus
/// > sepia/true-dark reading themes and semantic color tokens). This local copy
/// > covers only system/light/dark so the composition root can drive
/// > `preferredColorScheme` today. When P0.2 lands, re-point ``AppPreferences``
/// > and the root modifier at the DesignSystem type.
public enum ThemeMode: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// A user-facing label for pickers.
    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The `ColorScheme` to force, or `nil` to follow the system setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
