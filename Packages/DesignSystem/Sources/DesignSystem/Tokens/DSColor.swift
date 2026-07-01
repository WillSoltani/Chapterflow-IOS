import SwiftUI

/// Semantic color tokens for ChapterFlow.
///
/// Every token resolves to a *dynamic* color that adapts to light and dark
/// appearance automatically (backed by `UIColor(dynamicProvider:)`), so callers
/// never branch on `colorScheme`. Components must use these tokens rather than
/// literal colors — this is the single source of truth for the palette.
///
/// The palette is deliberately calm and typographic in the Apple "Pro" spirit:
/// near-neutral surfaces, high-contrast ink for text, and a single restrained
/// accent. Nothing here is flashy.
public enum DSColor {
    // MARK: Surfaces

    /// The base app background (behind everything).
    public static let background = Color(light: 0xFFFFFF, dark: 0x000000)

    /// A grouped/secondary surface that sits on top of `background`.
    public static let surface = Color(light: 0xF6F6F8, dark: 0x1C1C1E)

    /// A raised surface for cards, sheets and popovers.
    public static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x2C2C2E)

    // MARK: Text

    /// Primary reading/label ink — maximum legible contrast.
    public static let textPrimary = Color(light: 0x1A1A1C, dark: 0xF5F5F7)

    /// Secondary text — captions, supporting copy.
    public static let textSecondary = Color(light: 0x6B6B70, dark: 0xAEAEB2)

    /// Tertiary text — the quietest labels, placeholders, disabled.
    public static let textTertiary = Color(light: 0x9A9AA0, dark: 0x7C7C82)

    // MARK: Brand & status

    /// The single restrained brand accent (a refined slate indigo).
    public static let accent = Color(light: 0x3B5BA9, dark: 0x8AA1F0)

    /// Foreground drawn on top of `accent` (e.g. primary button labels).
    public static let onAccent = Color(light: 0xFFFFFF, dark: 0x0B0B12)

    /// Positive / success status.
    public static let success = Color(light: 0x2E7D51, dark: 0x30D158)

    /// Cautionary / warning status.
    public static let warning = Color(light: 0xB26B00, dark: 0xFFD34E)

    /// Destructive / error status.
    public static let danger = Color(light: 0xC0392B, dark: 0xFF453A)

    // MARK: Lines

    /// Hairline separators and borders.
    public static let separator = Color(light: 0x3C3C43, lightAlpha: 0.18,
                                        dark: 0xEBEBF5, darkAlpha: 0.20)
}

// MARK: - Dynamic color helpers

extension Color {
    /// Builds a dynamic `Color` from light/dark hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    /// Builds a dynamic `Color` from light/dark hex values with per-mode alpha.
    init(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    /// Creates a color from a 24-bit `0xRRGGBB` hex value.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
