import SwiftUI
import CoreKit
import AuthKit

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own `AuthService` (Amplify operations) and `SessionManager` (session lifecycle).
/// - Expose `authService` to `AuthFlowView` for the sign-in/sign-up forms.
/// - Track the user's display name resolved from the Cognito id_token JWT.
/// - Own the currently selected tab and per-tab `Router` navigation stacks.
/// - Parse incoming deep-link URLs and route them to the correct tab.
@Observable
@MainActor
public final class AppModel {

    // MARK: - Auth

    public let authService: AuthService
    public let session: SessionManager

    // MARK: - User profile

    /// Display name resolved from the Cognito id_token JWT.
    /// Falls back to `"Reader"` when signed in with no name claims.
    public internal(set) var displayName: String = ""

    // MARK: - Tab selection

    public var selectedTab: AppTab = .home

    // MARK: - Per-tab routers

    public let homeRouter     = Router()
    public let libraryRouter  = Router()
    public let reviewsRouter  = Router()
    public let profileRouter  = Router()
    public let settingsRouter = Router()

    // MARK: - Init

    public init(config: AppConfig = .fromInfoPlist()) {
        let svc = AuthService(config: config)
        self.authService = svc
        self.session = SessionManager(authService: svc)
        #if os(iOS)
        session.registerBackgroundRefresh()
        #endif
    }

    // MARK: - Lifecycle

    /// Configures Amplify and starts the auth-events listener. Call once at launch.
    public func configure() throws {
        try session.configure()
    }

    // MARK: - Display name

    /// Resolves and caches the display name from the stored id_token JWT.
    /// Call after `authState` transitions to `.signedIn`.
    public func hydrateDisplayName() {
        // 1. JWT claims (Cognito stores the name attribute).
        if let token = session.currentIdToken(),
           let profile = UserProfile.from(idToken: token),
           !profile.displayName.isEmpty {
            displayName = profile.displayName
            return
        }
        // 2. Display name persisted from Apple's first-sign-in disclosure.
        if let stored = UserDefaults.standard.string(forKey: "chapterflow.displayName"),
           !stored.isEmpty {
            displayName = stored
            return
        }
        // 3. Username from UserSummary (may be display name for SIWA path).
        if case .signedIn(let user) = session.authState, !user.username.isEmpty {
            displayName = user.username
            return
        }
        displayName = "Reader"
    }

    // MARK: - Deep-link handling

    public func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(deepLink: link)
    }

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
    }
}
