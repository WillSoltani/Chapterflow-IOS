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

/// The top-level routing shell for ChapterFlow.
///
/// Owns a fully-wired `AppModel` (session + identity bootstrap + deep-link
/// routing). Switches between the splash screen, auth flow, main tab shell,
/// and account-status screens based on `model.launchState`.
public struct AppRootView: View {
    @State private var model = AppModel.production()

    public init() {}

    public var body: some View {
        Group {
            switch model.launchState {
            case .loading:
                SplashView()

            case .signedOut:
                AuthFlowView(sessionManager: model.session) {
                    Task { await model.bootstrap() }
                }

            case .signedIn:
                mainTabView

            case .accountDeactivated:
                AccountStatusView(status: .deactivated) { model.signOut() }

            case .accountDeleted:
                AccountStatusView(status: .deleted) { model.signOut() }
            }
        }
        .environment(\.currentUser, model.currentUser)
        .task { await model.bootstrap() }
        .onChange(of: model.session.authState) { _, newState in
            // React when SessionManager signs out externally (e.g. token refresh failed).
            if newState == .signedOut {
                model.handleSessionSignOut()
            }
        }
        .onOpenURL { url in
            model.handle(url: url)
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                PlaceholderTab(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.cfAccent)
        .sheet(isPresented: Binding(
            get: { model.session.authState == .reauthRequired },
            set: { _ in }
        )) {
            ReauthView(sessionManager: model.session)
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

// MARK: - Previews

#Preview("Splash") {
    SplashView()
}

#Preview("Auth Flow") {
    AuthFlowView(sessionManager: SessionManager())
}

#Preview("Tab Shell — Signed In") {
    // Signed-in preview without a real network loader.
    let store = UserProfileStore(defaults: UserDefaults(suiteName: "approot-preview")!)
    store.save(UserProfile(
        sub: "preview-sub",
        email: "preview@example.com",
        displayName: "Preview User"
    ))
    let session = SessionManager(
        tokenStore: InMemoryTokenStore(idToken: "preview-tok", refreshToken: "preview-ref")
    )
    let model = AppModel(session: session, profileStore: store)
    return TabView(selection: .constant(AppTab.home)) {
        ForEach(AppTab.allCases, id: \.self) { tab in
            PlaceholderTab(tab: tab)
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
        }
    }
    .tint(.cfAccent)
    .environment(\.currentUser, model.currentUser)
}

#Preview("Account Deactivated") {
    AccountStatusView(status: .deactivated, onSignOut: {})
}

#Preview("Account Deleted") {
    AccountStatusView(status: .deleted, onSignOut: {})
}
