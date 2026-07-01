import SwiftUI
import Observation

/// Owns the navigation state for the whole shell: which tab is selected and one
/// `NavigationPath` per tab.
///
/// Each tab's `NavigationStack` binds to its path (`$router.libraryPath`, …).
/// Deep links are applied via ``apply(_:)``, which selects the target tab and
/// pushes the destination. Keeping a path *per tab* means switching tabs
/// preserves each tab's drill-down state, matching first-party app behavior.
@MainActor
@Observable
public final class TabRouter {
    /// The currently-selected tab.
    public var selectedTab: Tab

    public var homePath = NavigationPath()
    public var libraryPath = NavigationPath()
    public var reviewsPath = NavigationPath()
    public var profilePath = NavigationPath()
    public var settingsPath = NavigationPath()

    public init(selectedTab: Tab = .home) {
        self.selectedTab = selectedTab
    }

    /// Applies a resolved deep-link target: switches to its tab and, when the
    /// target carries a route, pushes it onto that tab's stack.
    public func apply(_ target: DeepLinkTarget) {
        switch target {
        case .tabRoot(let tab):
            selectedTab = tab
        case .home(let route):
            selectedTab = .home
            homePath.append(route)
        case .library(let route):
            selectedTab = .library
            libraryPath.append(route)
        case .reviews(let route):
            selectedTab = .reviews
            reviewsPath.append(route)
        case .profile(let route):
            selectedTab = .profile
            profilePath.append(route)
        case .settings(let route):
            selectedTab = .settings
            settingsPath.append(route)
        }
    }

    /// The number of pushed destinations on a tab's stack (diagnostics/tests).
    public func depth(of tab: Tab) -> Int {
        switch tab {
        case .home: return homePath.count
        case .library: return libraryPath.count
        case .reviews: return reviewsPath.count
        case .profile: return profilePath.count
        case .settings: return settingsPath.count
        }
    }

    /// Pops a tab's stack back to its root.
    public func popToRoot(_ tab: Tab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .reviews: reviewsPath = NavigationPath()
        case .profile: profilePath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }
}
