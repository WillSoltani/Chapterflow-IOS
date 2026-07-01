import CoreGraphics

/// Spacing tokens on a strict 4-pt grid. Use these for padding, gaps and insets
/// so rhythm stays consistent across the app.
public enum DSSpacing {
    /// 4 pt
    public static let xs: CGFloat = 4
    /// 8 pt
    public static let sm: CGFloat = 8
    /// 16 pt
    public static let md: CGFloat = 16
    /// 24 pt
    public static let lg: CGFloat = 24
    /// 32 pt
    public static let xl: CGFloat = 32
    /// 48 pt
    public static let xxl: CGFloat = 48
}

/// Corner-radius tokens. `pill` is an effectively-infinite radius for capsules.
public enum DSRadius {
    /// 6 pt
    public static let sm: CGFloat = 6
    /// 10 pt
    public static let md: CGFloat = 10
    /// 16 pt
    public static let lg: CGFloat = 16
    /// 24 pt
    public static let xl: CGFloat = 24
    /// Fully rounded (capsule).
    public static let pill: CGFloat = 999
}
