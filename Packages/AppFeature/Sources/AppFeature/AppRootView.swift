import SwiftUI
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
/// - `.unknown`        → `ProgressView` (Amplify resolving startup state)
/// - `.signedOut`      → `AuthFlowView` (Welcome / sign-in + email flows)
/// - `.signedIn`       → main `TabView` (sidebarAdaptable, Liquid Glass tab bar)
/// - `.reconnecting`   → main `TabView` + non-destructive top banner
/// - `.reauthRequired` → main `TabView` + `ReauthView` sheet (blocking)
public struct AppRootView: View {
    @State private var model: AppModel

    public init(config: AppConfig = .fromInfoPlist()) {
        _model = State(initialValue: AppModel(config: config))
    }

    public var body: some View {
        gatedContent
            .task { try? model.configure() }
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

    // MARK: - Auth-gated root content

    @ViewBuilder
    private var gatedContent: some View {
        switch model.session.authState {
        case .unknown:
            ProgressView()
                .accessibilityLabel("Loading")

        case .signedOut:
            authFlowContent

        case .signedIn, .reauthRequired, .reconnecting:
            mainTabView
                .sheet(isPresented: .constant(model.session.authState == .reauthRequired)) {
                    ReauthView(sessionManager: model.session)
                        .interactiveDismissDisabled(true)
                }
                .overlay(alignment: .top) {
                    if model.session.authState == .reconnecting {
                        ReconnectingBanner()
                            .animation(.spring, value: model.session.authState)
                    }
                }
        }
    }

    @ViewBuilder
    private var authFlowContent: some View {
        #if os(iOS)
        AuthFlowView(authService: model.authService)
        #else
        EmptyView()
        #endif
    }

    // MARK: - Main tab view

    /// Five-tab shell using the iOS 18 `Tab { }` API with `.sidebarAdaptable`
    /// so iPad gets a collapsible sidebar and iPhone/Mac get a native tab bar
    /// (which receives the Liquid Glass treatment automatically on iOS/macOS 26+).
    private var mainTabView: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTab(displayName: model.displayName)
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                PlaceholderTab(tab: .library)
            }
            Tab("Reviews", systemImage: "star", value: AppTab.reviews) {
                PlaceholderTab(tab: .reviews)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                PlaceholderTab(tab: .profile)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                PlaceholderTab(tab: .settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.cfAccent)
    }

    // MARK: - Tab content

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

/// A floating glass pill shown when the app is attempting to reconnect.
private struct ReconnectingBanner: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: .cfSpacing8) {
            ProgressView().scaleEffect(0.8)
            Text("Reconnecting…").font(.cfFootnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(bannerBackground, in: Capsule())
        .padding(.top, .cfSpacing8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Reconnecting to the server")
    }

    private var bannerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Previews

#Preview("Tab Shell — signed in") {
    AppRootView()
}

#Preview("Reconnecting banner") {
    ReconnectingBanner()
}
