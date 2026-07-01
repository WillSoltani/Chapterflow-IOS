import SwiftUI

/// The ChapterFlow type scale, mapped onto the system Dynamic Type text styles
/// so every token scales with the user's preferred content size automatically.
///
/// Two families are used, in the Apple "Pro" spirit:
/// - **Reading body** uses a refined serif (`.serif` → *New York*) for long-form
///   content, which reads warmer and more book-like.
/// - **UI text** uses the default SF Pro family for chrome, labels and controls.
///
/// Prefer the named tokens; drop to ``scaledFont(_:design:weight:)`` only when a
/// bespoke combination is genuinely needed.
public enum DSTypography {
    // MARK: Display & titles (SF Pro)

    public static var largeTitle: Font { scaledFont(.largeTitle, weight: .bold) }
    public static var title: Font { scaledFont(.title, weight: .bold) }
    public static var title2: Font { scaledFont(.title2, weight: .semibold) }
    public static var headline: Font { scaledFont(.headline, weight: .semibold) }

    // MARK: Body

    /// Long-form reading body — the refined serif. Use this inside the reader.
    public static var body: Font { scaledFont(.body, design: .serif) }

    /// UI body — SF Pro. Use this for controls, rows and non-reading copy.
    public static var bodyUI: Font { scaledFont(.body) }

    // MARK: Supporting (SF Pro)

    public static var callout: Font { scaledFont(.callout) }
    public static var subheadline: Font { scaledFont(.subheadline) }
    public static var footnote: Font { scaledFont(.footnote) }
    public static var caption: Font { scaledFont(.caption) }

    // MARK: Builder

    /// Builds a Dynamic-Type-scaled font for the given text style.
    ///
    /// `Font.system(_:design:)` is intrinsically relative to the user's
    /// preferred content size, so the result honours Dynamic Type (including the
    /// accessibility sizes) without any extra `@ScaledMetric` wiring.
    public static func scaledFont(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(style, design: design).weight(weight)
    }
}
