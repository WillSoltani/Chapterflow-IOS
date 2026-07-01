import SwiftUI

// Bring every workspace module into the composition root so the dependency
// graph is exercised. These are placeholders today; feature views will be
// mounted into the tabs below as each module is built out.
import CoreKit
import DesignSystem
import Models
import Networking
import Persistence
import AuthKit
import LibraryFeature
import ReaderFeature
import QuizFeature
import PaywallFeature
import EngagementFeature
import AIFeature
import SocialFeature
import NotificationsFeature
import OnboardingFeature
import SettingsFeature

/// The top-level tab shell for ChapterFlow.
///
/// This is a placeholder scaffold: five tabs, each showing its name. Real
/// feature views from the corresponding modules will replace the placeholders.
public struct AppRootView: View {
    public init() {}

    public var body: some View {
        TabView {
            PlaceholderTab(title: "Home", systemImage: "house")
                .tabItem { Label("Home", systemImage: "house") }

            PlaceholderTab(title: "Library", systemImage: "books.vertical")
                .tabItem { Label("Library", systemImage: "books.vertical") }

            PlaceholderTab(title: "Reviews", systemImage: "star")
                .tabItem { Label("Reviews", systemImage: "star") }

            PlaceholderTab(title: "Profile", systemImage: "person.crop.circle")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }

            PlaceholderTab(title: "Settings", systemImage: "gearshape")
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// A simple placeholder screen used by every tab until real features land.
private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("\(title) is coming soon.")
            )
            .navigationTitle(title)
        }
    }
}

#Preview {
    AppRootView()
}
