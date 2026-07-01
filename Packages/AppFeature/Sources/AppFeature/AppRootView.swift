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

/// The top-level entry point for the app's UI.
///
/// Gates content on `AuthState`:
/// - `.signedOut`      → `AuthFlowView` (Welcome / sign-in)
/// - `.signedIn`       → main `TabView`
/// - `.reconnecting`   → main `TabView` + a non-destructive top banner
/// - `.reauthRequired` → main `TabView` + `ReauthView` sheet (blocking)
///
/// `AppModel` is initialised with the live `AppConfig` so the production
/// `CognitoTokenRefresher` and `CognitoTokenClient` are wired in from first launch.
public struct AppRootView: View {
    @State private var model: AppModel

    public init(config: AppConfig = .fromInfoPlist()) {
        _model = State(initialValue: AppModel(config: config))
    }

    public var body: some View {
        Group {
            if case .signedOut = model.session.authState {
                AuthFlowView(
                    sessionManager: model.session,
                    cognitoClient: model.cognitoClient
                ) { name in
                    model.displayName = name
                }
            } else {
                mainTabView
                    // Reauth sheet — non-dismissable; user must confirm or cancel.
                    .sheet(isPresented: .constant(model.session.authState == .reauthRequired)) {
                        ReauthView(sessionManager: model.session)
                            .interactiveDismissDisabled(true)
                    }
                    // Reconnecting banner over the tabs (non-blocking).
                    .overlay(alignment: .top) {
                        if model.session.authState == .reconnecting {
                            ReconnectingBanner()
                                .animation(.spring, value: model.session.authState)
                        }
                    }
            }
        }
        .onOpenURL { url in model.handle(url: url) }
        .onChange(of: model.session.authState) { _, newState in
            switch newState {
            case .signedIn:
                model.hydrateDisplayName()
            case .signedOut:
                model.displayName = ""
            default:
                break
            }
        }
    }

    // MARK: - Main tab view

    private var mainTabView: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.cfAccent)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeTab(displayName: model.displayName)
        default:
            PlaceholderTab(tab: tab)
        }
    }
}

// MARK: - Home tab

/// Placeholder Home — shows the signed-in user's display name.
/// Replaced by `LibraryFeature.HomeView` in Phase 2.
private struct HomeTab: View {
    let displayName: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Home", systemImage: "house.fill")
            } description: {
                if displayName.isEmpty {
                    Text("Home is coming soon.")
                } else {
                    Text("Welcome, \(displayName).")
                }
            }
            .navigationTitle("Home")
        }
    }
}

// MARK: - Placeholder tab

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

// MARK: - Reconnecting banner

/// Non-blocking top banner shown while `AuthState == .reconnecting`.
private struct ReconnectingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Reconnecting…")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Reconnecting to the server")
    }
}

// MARK: - Previews

#Preview("Tab Shell — signed in") {
    AppRootView(config: AppConfig(
        apiBaseURL: "",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "",
        cognitoClientID: "",
        cognitoDomain: ""
    ))
}

#Preview("Welcome — signed out") {
    // Start with no stored token so AppModel initialises to .signedOut.
    AppRootView(config: AppConfig(
        apiBaseURL: "",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "",
        cognitoClientID: "",
        cognitoDomain: ""
    ))
}

#Preview("Reconnecting banner") {
    ReconnectingBanner()
}
