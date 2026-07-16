import SwiftUI

/// Stable semantic typography roles for ChapterFlow's editorial surfaces.
///
/// Each role is backed by a native relative text style, so it follows Dynamic
/// Type through the full accessibility range without a fixed point-size cap.
public enum CFEditorialTextRole: String, CaseIterable, Hashable, Sendable {
    case display
    case screenTitle
    case sectionTitle
    case body
    case metadata
    case caption

    /// The native text style that controls Dynamic Type scaling for this role.
    public var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display:
            .largeTitle
        case .screenTitle:
            .title
        case .sectionTitle:
            .title3
        case .body:
            .body
        case .metadata:
            .subheadline
        case .caption:
            .caption
        }
    }

    /// Platform-native font treatment for this semantic role.
    public var font: Font {
        switch self {
        case .display:
            .system(relativeTextStyle, design: .serif, weight: .bold)
        case .screenTitle:
            .system(relativeTextStyle, design: .serif, weight: .semibold)
        case .sectionTitle:
            .system(relativeTextStyle, design: .default, weight: .semibold)
        case .body:
            .system(relativeTextStyle, design: .default, weight: .regular)
        case .metadata:
            .system(relativeTextStyle, design: .default, weight: .regular)
        case .caption:
            .system(relativeTextStyle, design: .default, weight: .medium)
        }
    }

    /// Extra leading for multi-line readability without constraining height.
    public var lineSpacing: CGFloat {
        switch self {
        case .display, .screenTitle:
            2
        case .sectionTitle, .metadata, .caption:
            1
        case .body:
            4
        }
    }
}

/// ChapterFlow typography scale.
///
/// Built on Dynamic Type so all sizes adapt to the user's preferred text size.
/// Every UI label must use one of these instead of a raw `Font` value.
public extension Font {
    // MARK: Editorial semantics

    static let cfEditorialDisplay = CFEditorialTextRole.display.font
    static let cfScreenTitle = CFEditorialTextRole.screenTitle.font
    static let cfSectionTitle = CFEditorialTextRole.sectionTitle.font
    static let cfEditorialBody = CFEditorialTextRole.body.font
    static let cfMetadata = CFEditorialTextRole.metadata.font
    static let cfEditorialCaption = CFEditorialTextRole.caption.font

    // MARK: Display

    static let cfLargeTitle  = Font.largeTitle.weight(.bold)
    static let cfTitle1      = Font.title.weight(.semibold)
    static let cfTitle2      = Font.title2.weight(.semibold)
    static let cfTitle3      = Font.title3.weight(.medium)

    // MARK: Body

    static let cfHeadline    = Font.headline
    static let cfSubheadline = Font.subheadline.weight(.medium)
    static let cfBody        = Font.body
    static let cfCallout     = Font.callout

    // MARK: Caption / Label

    static let cfCaption     = Font.caption.weight(.medium)
    static let cfCaption2    = Font.caption2.weight(.medium)
    static let cfFootnote    = Font.footnote

    // MARK: Reader

    /// Serif body font for the reading surface — respects Dynamic Type.
    @available(iOS 16.0, macOS 13.0, *)
    static func cfReaderBody(size: CGFloat = 17) -> Font {
        Font.system(size: size, weight: .regular, design: .serif)
    }
}

public extension View {
    /// Applies a semantic editorial font and its readable multi-line leading.
    func cfEditorialTextStyle(_ role: CFEditorialTextRole) -> some View {
        font(role.font)
            .lineSpacing(role.lineSpacing)
    }
}
