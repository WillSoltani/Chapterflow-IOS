import SwiftUI

/// A subtle elevation shadow token. Elevation in a "Pro" interface should be
/// felt, not seen — these values are intentionally soft and low-contrast.
public struct DSShadow: Sendable, Equatable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

public extension DSShadow {
    /// No elevation.
    static let none = DSShadow(color: .clear, radius: 0, y: 0)
    /// A whisper of lift — chips, inline controls.
    static let subtle = DSShadow(color: .black.opacity(0.06), radius: 4, y: 1)
    /// The default card elevation.
    static let card = DSShadow(color: .black.opacity(0.08), radius: 12, y: 4)
    /// Floating surfaces — sheets, toasts, popovers.
    static let elevated = DSShadow(color: .black.opacity(0.14), radius: 24, y: 10)
}

public extension View {
    /// Applies a design-system elevation shadow.
    func dsShadow(_ shadow: DSShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
