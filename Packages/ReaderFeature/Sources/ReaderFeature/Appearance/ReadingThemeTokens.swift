import SwiftUI
import Persistence

/// The full resolved color token set for a single reading theme.
///
/// Each theme is a curated palette tuned for extended reading comfort.
/// `system` delegates to iOS adaptive colors so it follows light/dark mode
/// automatically; every other theme is fixed regardless of the system setting.
public struct ReadingThemeTokens: Sendable {
    /// Full-bleed page background.
    public let pageBg: Color
    /// Primary narrative text.
    public let primaryText: Color
    /// Supporting / secondary text (labels, captions, attributions).
    public let secondaryText: Color
    /// Tertiary text (section labels, annotations).
    public let tertiaryText: Color
    /// Interactive and structural accent.
    public let accent: Color
    /// Pull-quote body text.
    public let quoteText: Color
    /// Vertical bar beside pull-quotes and key-takeaway stripes.
    public let quoteBar: Color
    /// Hairline separators between sections.
    public let separator: Color
    /// Surface tint for callout boxes, cards, and recap panels.
    public let surfaceBg: Color

    // MARK: - Factory

    /// Returns the resolved token set for `theme`.
    public static func tokens(for theme: ReadingTheme) -> ReadingThemeTokens {
        switch theme {
        case .system: return .systemTheme
        case .light:  return .lightTheme
        case .sepia:  return .sepiaTheme
        case .dark:   return .darkTheme
        case .paper:  return .paperTheme
        }
    }
}

// MARK: - Theme definitions

extension ReadingThemeTokens {

    // MARK: System — follows iOS light / dark mode

#if canImport(UIKit)
    static let systemTheme = ReadingThemeTokens(
        pageBg:        Color(UIColor.systemBackground),
        primaryText:   Color(UIColor.label),
        secondaryText: Color(UIColor.secondaryLabel),
        tertiaryText:  Color(UIColor.tertiaryLabel),
        accent:        Color(red: 0.18, green: 0.40, blue: 0.82),
        quoteText:     Color(UIColor.secondaryLabel),
        quoteBar:      Color(red: 0.18, green: 0.40, blue: 0.82, opacity: 0.70),
        separator:     Color(UIColor.separator),
        surfaceBg:     Color(UIColor.secondarySystemBackground)
    )
#else
    static let systemTheme = ReadingThemeTokens(
        pageBg:        Color(NSColor.windowBackgroundColor),
        primaryText:   Color(NSColor.labelColor),
        secondaryText: Color(NSColor.secondaryLabelColor),
        tertiaryText:  Color(NSColor.tertiaryLabelColor),
        accent:        Color(red: 0.18, green: 0.40, blue: 0.82),
        quoteText:     Color(NSColor.secondaryLabelColor),
        quoteBar:      Color(red: 0.18, green: 0.40, blue: 0.82, opacity: 0.70),
        separator:     Color(NSColor.separatorColor),
        surfaceBg:     Color(NSColor.underPageBackgroundColor)
    )
#endif

    // MARK: Light — clean white, always light

    static let lightTheme = ReadingThemeTokens(
        pageBg:        Color(white: 1.00),
        primaryText:   Color(white: 0.09),
        secondaryText: Color(white: 0.38),
        tertiaryText:  Color(white: 0.55),
        accent:        Color(red: 0.18, green: 0.40, blue: 0.82),
        quoteText:     Color(white: 0.35),
        quoteBar:      Color(red: 0.18, green: 0.40, blue: 0.82, opacity: 0.65),
        separator:     Color(white: 0.82),
        surfaceBg:     Color(white: 0.95)
    )

    // MARK: Sepia — premium warm cream (inspired by Kindle Paperwhite amber)

    /// Warm cream background with rich brown text.
    /// Reduced blue-light content makes long evening sessions comfortable.
    static let sepiaTheme = ReadingThemeTokens(
        pageBg:        Color(red: 0.961, green: 0.941, blue: 0.898), // #F5F0E5
        primaryText:   Color(red: 0.235, green: 0.169, blue: 0.118), // #3C2B1E
        secondaryText: Color(red: 0.447, green: 0.322, blue: 0.235), // #72523C
        tertiaryText:  Color(red: 0.604, green: 0.478, blue: 0.384), // #9A7A62
        accent:        Color(red: 0.651, green: 0.384, blue: 0.165), // #A6622A amber
        quoteText:     Color(red: 0.447, green: 0.322, blue: 0.235),
        quoteBar:      Color(red: 0.651, green: 0.384, blue: 0.165, opacity: 0.75),
        separator:     Color(red: 0.784, green: 0.722, blue: 0.604), // #C8B89A
        surfaceBg:     Color(red: 0.922, green: 0.894, blue: 0.835)  // #EBE4D5
    )

    // MARK: Dark — OLED true-black

    /// `#000000` page background eliminates power draw on OLED panels.
    /// Contrast ratios are tuned to avoid glare without losing legibility.
    static let darkTheme = ReadingThemeTokens(
        pageBg:        Color(white: 0.00),                            // OLED #000000
        primaryText:   Color(white: 0.90),                            // #E6E6E6
        secondaryText: Color(white: 0.58),
        tertiaryText:  Color(white: 0.40),
        accent:        Color(red: 0.50, green: 0.72, blue: 1.00),     // sky blue
        quoteText:     Color(white: 0.62),
        quoteBar:      Color(red: 0.45, green: 0.60, blue: 0.90, opacity: 0.75),
        separator:     Color(white: 0.14),
        surfaceBg:     Color(white: 0.08)
    )

    // MARK: Paper — warm off-white, e-ink feel

    /// Warmer than pure white, less saturated than sepia.
    /// Ideal for daytime reading with natural light.
    static let paperTheme = ReadingThemeTokens(
        pageBg:        Color(red: 0.980, green: 0.969, blue: 0.949), // #FAF7F2
        primaryText:   Color(red: 0.118, green: 0.110, blue: 0.094), // #1E1C18
        secondaryText: Color(red: 0.478, green: 0.439, blue: 0.376), // #7A7060
        tertiaryText:  Color(red: 0.627, green: 0.580, blue: 0.518), // #A09484
        accent:        Color(red: 0.290, green: 0.435, blue: 0.647), // #4A6FA5
        quoteText:     Color(red: 0.478, green: 0.439, blue: 0.376),
        quoteBar:      Color(red: 0.580, green: 0.510, blue: 0.400, opacity: 0.80),
        separator:     Color(red: 0.847, green: 0.820, blue: 0.780),
        surfaceBg:     Color(red: 0.941, green: 0.922, blue: 0.890)  // #F0EBE3
    )
}
