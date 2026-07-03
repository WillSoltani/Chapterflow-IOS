import SwiftUI

public extension Color {
    /// Creates a `Color` from a CSS-style hex string (`"#RRGGBB"` or `"RRGGBB"`).
    /// Returns `.cfAccent` when the string cannot be parsed so the UI never breaks.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            self = .cfAccent
            return
        }

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
