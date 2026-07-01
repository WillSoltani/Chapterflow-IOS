import SwiftUI

/// The five top-level tabs of the ChapterFlow app shell.
///
/// Used as the `TabView` selection type in `AppRootView` and as the routing
/// target in `AppModel.handle(deepLink:)`.
public enum AppTab: Int, CaseIterable, Hashable, Sendable {
    case home
    case library
    case reviews
    case profile
    case settings

    public var title: String {
        switch self {
        case .home:     return "Home"
        case .library:  return "Library"
        case .reviews:  return "Reviews"
        case .profile:  return "Profile"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home:     return "house"
        case .library:  return "books.vertical"
        case .reviews:  return "star"
        case .profile:  return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }

    public var filledSystemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .library:  return "books.vertical.fill"
        case .reviews:  return "star.fill"
        case .profile:  return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
