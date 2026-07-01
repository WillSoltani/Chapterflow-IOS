import SwiftUI

// Cross-platform semantic colors. The shipping target is iOS, but the package
// also compiles on the macOS host for `swift test`, where UIKit's system colors
// don't exist. These resolve to the right system color on each platform.
//
// > When DesignSystem (P0.2) lands, replace these with its semantic color
// > tokens (`Color.dsBackground`, …) per the "never hardcode colors" rule.
extension Color {
    /// The primary system background (window background on macOS).
    static var appBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }
}
