import SwiftUI
import CoreKit
import AuthKit
import Networking

// MARK: - Launch state

/// Top-level routing state; drives which root view `AppRootView` renders.
public enum LaunchState: Sendable, Equatable {
    /// Session is being validated — show the splash screen.
    case loading
    /// No valid session — show the auth flow.
    case signedOut
    /// Valid session with a hydrated user — show the main tab shell.
    case signedIn
    /// The server reports the account has been deactivated.
    case accountDeactivated
    /// The server reports the account has been deleted.
    case accountDeleted
}

// MARK: - AppModel

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own the `SessionManager` (auth state + token lifecycle).
/// - Bootstrap identity on cold start: validate session via
///   `GET /auth/session` + hydrate `UserProfile` from `GET /me`.
/// - Persist a minimal `UserProfile` for instant-launch display.
/// - Expose `currentUser` for downstream features (via `EnvironmentValues`).
/// - Own the currently selected tab and a `Router` per tab.
/// - Parse incoming deep-link URLs and route them to the correct tab.
@Observable
@MainActor
public final class AppModel {

    // MARK: Session

    public let session: SessionManager

    // MARK: Identity / launch state

    public private(set) var launchState: LaunchState
    public private(set) var currentUser: UserProfile?

    // MARK: Tab selection

    public var selectedTab: AppTab = .home

    // MARK: Per-tab routers

    public let homeRouter     = Router()
    public let libraryRouter  = Router()
    public let reviewsRouter  = Router()
    public let profileRouter  = Router()
    public let settingsRouter = Router()

    // MARK: Private

    private let identityLoader: (any IdentityLoading)?
    private let profileStore: UserProfileStore
    private var isBootstrapping = false

    // MARK: Init

    /// Primary init — pass `identityLoader: nil` for tests / previews.
    public init(
        session: SessionManager = SessionManager(),
        identityLoader: (any IdentityLoading)? = nil,
        profileStore: UserProfileStore = .shared
    ) {
        self.session = session
        self.identityLoader = identityLoader
        self.profileStore = profileStore

        if identityLoader == nil {
            // Tests / previews: resolve synchronously from the session's current auth state.
            self.launchState = session.authState == .signedIn ? .signedIn : .signedOut
        } else {
            // Production: tokens present → splash while we validate; absent → auth flow.
            self.launchState = session.authState == .signedIn ? .loading : .signedOut
        }
    }

    // MARK: Production factory

    /// Creates a fully-wired `AppModel` backed by a live `APIClient`.
    /// Called from `AppRootView` via `@State`.
    public static func production() -> AppModel {
        let session = SessionManager()
        let config = AppConfig.fromInfoPlist()
        let apiClient = APIClient(config: config, tokenProvider: session)
        let loader = NetworkIdentityLoader(apiClient: apiClient)
        return AppModel(session: session, identityLoader: loader)
    }

    // MARK: Bootstrap

    /// Validates the Cognito session and hydrates `currentUser`. Called from
    /// `AppRootView.task` on first appear and after a successful sign-in.
    /// Concurrent calls are coalesced via the `isBootstrapping` guard.
    public func bootstrap() async {
        guard let loader = identityLoader, !isBootstrapping else { return }
        guard session.authState == .signedIn else {
            launchState = .signedOut
            return
        }

        isBootstrapping = true
        defer { isBootstrapping = false }

        // Optimistic instant-launch: surface the cached profile immediately.
        if let cached = profileStore.load() {
            currentUser = cached
            launchState = .signedIn
        }

        // Step 1: validate session with the server.
        let sessionResult: SessionLoadResult
        do {
            sessionResult = try await loader.loadSession()
        } catch {
            // Network failure — keep the user signed in if there is a cached profile;
            // otherwise sign them out so they aren't trapped on the splash screen.
            if launchState == .loading {
                launchState = currentUser != nil ? .signedIn : .signedOut
            }
            return
        }

        switch sessionResult {
        case .invalid:
            session.signOut()
            profileStore.clear()
            currentUser = nil
            launchState = .signedOut
            return
        case .deactivated:
            launchState = .accountDeactivated
            return
        case .deleted:
            launchState = .accountDeleted
            return
        case .valid:
            break
        }

        // Step 2: hydrate a fresh profile from the server.
        do {
            let profile = try await loader.loadProfile()
            currentUser = profile
            profileStore.save(profile)
            switch profile.accountStatus {
            case .deactivated: launchState = .accountDeactivated
            case .deleted:     launchState = .accountDeleted
            case .active:      launchState = .signedIn
            }
        } catch {
            // Profile fetch failed but session is valid; surface whatever we have.
            if launchState == .loading {
                launchState = currentUser != nil ? .signedIn : .signedOut
            }
        }
    }

    // MARK: Auth transitions

    /// Signs the user out, clears all persisted identity, and returns to the auth flow.
    public func signOut() {
        session.signOut()
        profileStore.clear()
        currentUser = nil
        launchState = .signedOut
    }

    /// Reacts when `SessionManager` signs out externally (e.g. token refresh fails).
    /// Does NOT call `session.signOut()` again — the session is already terminated.
    public func handleSessionSignOut() {
        profileStore.clear()
        currentUser = nil
        launchState = .signedOut
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
