import CoreFoundation

/// ChapterFlow spacing and radius tokens (in points).
///
/// Use these for paddings, margins, gaps, and corner radii. Never use raw
/// numeric literals in layout code — always reference a token so the grid
/// stays consistent.
public extension CGFloat {
    // MARK: Spacing grid (base-4)

    static let cfSpacing2:  CGFloat = 2
    static let cfSpacing4:  CGFloat = 4
    static let cfSpacing8:  CGFloat = 8
    static let cfSpacing12: CGFloat = 12
    static let cfSpacing16: CGFloat = 16
    static let cfSpacing20: CGFloat = 20
    static let cfSpacing24: CGFloat = 24
    static let cfSpacing32: CGFloat = 32
    static let cfSpacing40: CGFloat = 40
    static let cfSpacing48: CGFloat = 48
    static let cfSpacing64: CGFloat = 64

    // MARK: Corner radii

    static let cfRadius4:  CGFloat = 4
    static let cfRadius8:  CGFloat = 8
    static let cfRadius12: CGFloat = 12
    static let cfRadius16: CGFloat = 16
    static let cfRadius20: CGFloat = 20
    static let cfRadius24: CGFloat = 24

    // MARK: Icon sizes

    static let cfIconSmall:  CGFloat = 20
    static let cfIconMedium: CGFloat = 28
    static let cfIconLarge:  CGFloat = 44
}
