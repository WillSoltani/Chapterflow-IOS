import SwiftUI
import CoreKit
import Networking
import Persistence
import AuthKit

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own the currently selected tab.
/// - Own a `Router` per tab so each tab's navigation stack is preserved when
///   the user switches away and back.
/// - Parse incoming deep-link URLs and route them to the correct tab (and, in
///   later phases, push the right destination onto that tab's router).
/// - Own `AuthService` and `APIClient`; expose them to child feature views.
@Observable
@MainActor
public final class AppModel {

    // MARK: Tab selection

    public var selectedTab: AppTab = .home

    // MARK: Per-tab routers

    public let homeRouter     = Router()
    public let libraryRouter  = Router()
    public let reviewsRouter  = Router()
    public let profileRouter  = Router()
    public let settingsRouter = Router()

    // MARK: Auth & Networking

    /// Drives authentication state across the app.
    public let authService: AuthService

    /// Pre-wired `APIClient` authenticated via `authService`.
    /// Feature modules receive this via the environment or direct injection.
    public let apiClient: APIClient

    // MARK: Init

    public init(config: AppConfig = .fromInfoPlist()) {
        let tokenStore = TokenStore()
        let auth = AuthService(config: config, tokenStore: tokenStore)
        let provider = AuthTokenProvider(store: tokenStore, refresher: auth)
        self.authService = auth
        self.apiClient = APIClient(config: config, tokenProvider: provider)
    }

    // MARK: - Computed

    /// Returns `true` when the user has a valid signed-in session.
    public var isSignedIn: Bool {
        if case .signedIn = authService.authState { return true }
        return false
    }

    // MARK: - Lifecycle

    /// Configures Amplify and resolves the initial `authState`.
    /// Call once from the root view's `.task {}` modifier.
    public func configure() throws {
        try authService.configure()
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
        // Feature-level navigation (e.g. libraryRouter.push(.bookDetail(id:)))
        // will be wired here as the feature modules are built out in Phase 2+.
    }
}
