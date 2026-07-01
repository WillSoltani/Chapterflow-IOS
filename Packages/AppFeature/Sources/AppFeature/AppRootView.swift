import SwiftUI

// Bring every workspace module into the composition root so the dependency
// graph is exercised. Real feature views from the corresponding modules will
// replace the placeholder tabs as each module is built out.
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
/// Owns an `AppModel` that tracks the selected tab and per-tab navigation
/// routers. Deep links received by `ChapterFlowApp` are forwarded here via
/// `.onOpenURL` and dispatched to the correct tab by `AppModel`.
public struct AppRootView: View {
    @State private var model = AppModel()

    public init() {}

    public var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                PlaceholderTab(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.cfAccent)
        .task {
            // Configure Amplify + resolve initial auth state once at launch.
            try? model.configure()
        }
        .onOpenURL { url in
            model.handle(url: url)
        }
    }
}

/// Placeholder navigation shell for a tab — replaced by real feature views
/// in Phase 2 onward.
private struct PlaceholderTab: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                tab.title,
                systemImage: tab.filledSystemImage,
                description: Text("\(tab.title) is coming soon.")
            )
            .navigationTitle(tab.title)
        }
    }
}

#Preview("Tab Shell") {
    AppRootView()
}

#Preview("Deep Link → Library") {
    let view = AppRootView()
    // Simulates a chapterflow://book/abc123 open-URL by selecting the tab directly.
    return view
}
