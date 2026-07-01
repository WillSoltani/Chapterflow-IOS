import SwiftUI

/// ChapterFlow typography scale.
///
/// Built on Dynamic Type so all sizes adapt to the user's preferred text size.
/// Every UI label must use one of these instead of a raw `Font` value.
public extension Font {
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
