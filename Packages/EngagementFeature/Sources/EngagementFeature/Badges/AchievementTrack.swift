import Foundation

// MARK: - AchievementTrack

/// Maps the server `category` string to a named achievement track for display.
///
/// The four known tracks (mastery, consistency, exploration, hidden) correspond
/// to the four badge categories the server emits. Unrecognised future categories
/// land in `.other` so the app never crashes on a new server value.
public enum AchievementTrack: String, CaseIterable, Sendable, Hashable {
    // swiftlint:disable:next inclusive_language
    case mastery
    case consistency
    case exploration
    case hidden

    /// Construct a track from a server category string. Returns `nil` for unknown
    /// values so callers can decide how to handle future categories gracefully.
    public static func from(category: String) -> AchievementTrack? {
        AchievementTrack(rawValue: category.lowercased())
    }

    public var displayName: String {
        switch self {
        case .mastery:     return "Mastery"
        case .consistency: return "Consistency"
        case .exploration: return "Exploration"
        case .hidden:      return "Hidden"
        }
    }

    public var systemImage: String {
        switch self {
        case .mastery:     return "brain.head.profile"
        case .consistency: return "flame.fill"
        case .exploration: return "map.fill"
        case .hidden:      return "questionmark.circle.fill"
        }
    }
}
