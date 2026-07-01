import SwiftUI

/// ChapterFlow semantic color tokens.
///
/// All UI code must reference these instead of literal `Color` values so that
/// themes (dark mode, sepia reader) can be applied from a single source.
///
/// Platform note: tokens backed by `UIColor` names (iOS/iPadOS only) are
/// guarded with `#if canImport(UIKit)`. The macOS builds used for CLI testing
/// fall back to equivalent system colors.
public extension Color {
    // MARK: Brand

    /// Primary brand accent — a calm, deep blue used for interactive elements,
    /// tab indicators, and progress rings.
    static let cfAccent = Color(red: 0.18, green: 0.40, blue: 0.82)

    // MARK: Platform-specific semantic tokens

#if canImport(UIKit)
    static let cfLabel           = Color(.label)
    static let cfSecondaryLabel  = Color(.secondaryLabel)
    static let cfTertiaryLabel   = Color(.tertiaryLabel)
    static let cfQuaternaryLabel = Color(.quaternaryLabel)

    static let cfBackground          = Color(.systemBackground)
    static let cfSecondaryBackground = Color(.secondarySystemBackground)
    static let cfTertiaryBackground  = Color(.tertiarySystemBackground)
    static let cfGroupedBackground   = Color(.systemGroupedBackground)

    static let cfFill           = Color(.systemFill)
    static let cfSecondaryFill  = Color(.secondarySystemFill)

    static let cfSeparator       = Color(.separator)
    static let cfOpaqueSeparator = Color(.opaqueSeparator)
#else
    static let cfLabel           = Color(nsColor: .labelColor)
    static let cfSecondaryLabel  = Color(nsColor: .secondaryLabelColor)
    static let cfTertiaryLabel   = Color(nsColor: .tertiaryLabelColor)
    static let cfQuaternaryLabel = Color(nsColor: .quaternaryLabelColor)

    static let cfBackground          = Color(nsColor: .windowBackgroundColor)
    static let cfSecondaryBackground = Color(nsColor: .underPageBackgroundColor)
    static let cfTertiaryBackground  = Color(nsColor: .controlBackgroundColor)
    static let cfGroupedBackground   = Color(nsColor: .windowBackgroundColor)

    static let cfFill          = Color(nsColor: .controlColor)
    static let cfSecondaryFill = Color(nsColor: .controlColor)

    static let cfSeparator       = Color(nsColor: .separatorColor)
    static let cfOpaqueSeparator = Color(nsColor: .separatorColor)
#endif
}
