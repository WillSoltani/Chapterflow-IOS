import SwiftUI
import CoreKit
import AuthKit

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own the `SessionManager` (auth state + token lifecycle).
/// - Own a `CognitoTokenClient` for the sign-in flow.
/// - Track the user's display name (decoded from the Cognito id_token JWT).
/// - Own the currently selected tab.
/// - Own a `Router` per tab so each tab's navigation stack is preserved when
///   the user switches away and back.
/// - Parse incoming deep-link URLs and route them to the correct tab.
@Observable
@MainActor
public final class AppModel {

    // MARK: Session

    public let session: SessionManager
    public let cognitoClient: CognitoTokenClient

    // MARK: User profile

    /// The user's display name, resolved from the Cognito id_token JWT.
    /// Defaults to `""` when signed out and `"Reader"` when signed in but
    /// no name claim is present.
    public internal(set) var displayName: String = ""

    // MARK: Tab selection

    public var selectedTab: AppTab = .home

    // MARK: Per-tab routers

    public let homeRouter     = Router()
    public let libraryRouter  = Router()
    public let reviewsRouter  = Router()
    public let profileRouter  = Router()
    public let settingsRouter = Router()

    // MARK: Init

    /// Default init — used in unit tests and when no specific config is required.
    /// Uses `StubTokenRefresher` for the token refresh path.
    public init(session: SessionManager = SessionManager()) {
        self.session = session
        self.cognitoClient = CognitoTokenClient(config: .fromInfoPlist())
        if case .signedIn = session.authState { hydrateDisplayName() }
        registerBGTasks(session: session)
    }

    /// Config-based init used in production.
    /// Wires a real `CognitoTokenRefresher` into the session lifecycle.
    public init(config: AppConfig) {
        let refresher = CognitoTokenRefresher(config: config)
        let session = SessionManager(refresher: refresher)
        self.session = session
        self.cognitoClient = CognitoTokenClient(config: config)
        if case .signedIn = session.authState { hydrateDisplayName() }
        registerBGTasks(session: session)
    }

    private func registerBGTasks(session: SessionManager) {
        // BGTaskScheduler is iOS-only; the macOS test host skips this.
        #if os(iOS)
        session.registerBackgroundRefresh()
        #endif
    }

    // MARK: Display name

    /// Resolves and caches the display name from the stored id_token JWT.
    /// Call whenever auth state transitions to `.signedIn`.
    public func hydrateDisplayName() {
        // 1. Try JWT claims (Cognito stores the name attribute from Apple's first sign-in).
        if let token = session.currentIdToken(),
           let profile = UserProfile.from(idToken: token),
           !profile.displayName.isEmpty {
            displayName = profile.displayName
            return
        }
        // 2. Fallback: display name persisted from Apple's first-sign-in disclosure.
        if let stored = UserDefaults.standard.string(forKey: "chapterflow.displayName"),
           !stored.isEmpty {
            displayName = stored
            return
        }
        displayName = "Reader"
    }

    // MARK: Deep-link handling

    /// Parses `url` and routes to the matching tab/screen.
    /// Silently ignores URLs whose scheme isn't `chapterflow://`.
    public func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(deepLink: link)
    }

    /// Routes a parsed `DeepLink` to the appropriate tab and, where possible,
    /// pushes the matching destination onto that tab's navigation stack.
    public func handle(deepLink: DeepLink) {
        switch deepLink {
        case .book, .chapter:
            selectedTab = .library

        case .review:
            selectedTab = .reviews

        case .pairAccept, .gift:
            selectedTab = .profile

        case .unknown:
            break
        }
        // Feature-level navigation will be wired as modules are built in Phase 2+.
    }
}
