import SwiftUI

/// The colours the user can apply to a highlight.
///
/// Raw `String` values match what is sent to / received from the notebook API.
public enum HighlightColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case yellow
    case orange
    case green
    case blue
    case pink

    public var id: String { rawValue }

    /// The translucent tint used as the highlight background in the reader.
    public var swiftUIColor: Color {
        switch self {
        case .yellow: return Color.yellow.opacity(0.35)
        case .orange: return Color.orange.opacity(0.35)
        case .green:  return Color.green.opacity(0.30)
        case .blue:   return Color.blue.opacity(0.30)
        case .pink:   return Color.pink.opacity(0.30)
        }
    }

    /// Fully-opaque version used in colour pickers and badges.
    public var solidColor: Color {
        switch self {
        case .yellow: return .yellow
        case .orange: return .orange
        case .green:  return .green
        case .blue:   return .blue
        case .pink:   return .pink
        }
    }

    /// Short localised display name.
    public var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        }
    }
}
