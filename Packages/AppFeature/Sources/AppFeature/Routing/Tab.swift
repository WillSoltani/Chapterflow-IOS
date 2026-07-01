import SwiftUI

/// The five top-level tabs of the app shell.
public enum Tab: String, CaseIterable, Identifiable, Sendable {
    case home
    case library
    case reviews
    case profile
    case settings

    public var id: String { rawValue }

    /// The tab's title (also its accessibility label).
    public var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .reviews: return "Reviews"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    /// The SF Symbol shown in the tab bar.
    public var systemImage: String {
        switch self {
        case .home: return "house"
        case .library: return "books.vertical"
        case .reviews: return "star"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}
