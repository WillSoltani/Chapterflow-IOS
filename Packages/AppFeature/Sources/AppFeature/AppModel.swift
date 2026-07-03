import SwiftUI
import CoreKit
import AuthKit
import Networking
import Persistence
import LibraryFeature
import SocialFeature
import AIFeature

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own `AuthService` (Amplify operations) and `SessionManager` (session lifecycle).
/// - Expose `authService` to `AuthFlowView` for the sign-in/sign-up forms.
/// - Track the user's display name resolved from the Cognito id_token JWT.
/// - Own the currently selected tab and per-tab `Router` navigation stacks.
/// - Vend the shared `LibraryRepository` consumed by `HomeView` and `LibraryView`.
/// - Own the shared `AudioPlayerModel` (single instance, survives tab changes).
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

    // MARK: - Library

    /// Shared repository for the Home and Library tabs.
    public let libraryRepository: any LibraryRepository

    /// Shared repository for the Book Detail screen.
    public let bookDetailRepository: any BookDetailRepository

    // MARK: - Social

    /// Shared repository for all of Lane S — profile, pairs, gifts, reflections, referrals.
    public let socialRepository: any SocialRepository

    // MARK: - AI

    /// Shared repository for the "Ask the book" feature.
    public let aiRepository: any AIRepository

    /// Shared audio player model — the single, long-lived player that persists
    /// across tab switches and navigation stack pushes/pops.
    ///
    /// Injected into the view hierarchy via `.environment(\.audioPlayerModel, audioPlayerModel)`
    /// so any view can start or observe playback without prop-drilling.
    public let audioPlayerModel: AudioPlayerModel

    // MARK: - Init

    public init(config: AppConfig = .fromInfoPlist()) {
        let svc = AuthService(config: config)
        self.authService = svc
        let sm = SessionManager(authService: svc)
        self.session = sm

        let container = try? PersistenceController.makeDefault().container
        let client = APIClient(config: config, tokenProvider: sm)
        self.libraryRepository = LiveLibraryRepository(client: client, container: container)
        self.bookDetailRepository = LiveBookDetailRepository(client: client)
        self.socialRepository = LiveSocialRepository(client: client)
        self.aiRepository = LiveAIRepository(client: client)
        self.audioPlayerModel = AudioPlayerModel(repository: LiveAudioRepository(client: client))

        #if os(iOS)
        sm.registerBackgroundRefresh()
        #endif
        #if DEBUG
        // `--demo-tab=library` (etc.) lets simulator runs jump to a specific tab.
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--demo-tab=") }) {
            let name = String(arg.dropFirst("--demo-tab=".count))
            selectedTab = AppTab.allCases.first { $0.title.lowercased() == name.lowercased() } ?? .home
        }
        #endif
    }

    // MARK: - Lifecycle

    /// Configures Amplify, activates the AVAudioSession, and wires up lock-screen
    /// controls. Call once at app launch.
    public func configure() throws {
        try session.configure()
        audioPlayerModel.activateAudioSession()
        audioPlayerModel.setupRemoteCommands()
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
