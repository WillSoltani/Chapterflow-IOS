import SwiftUI
import CoreKit
import AuthKit
import Networking
import Persistence
import LibraryFeature
import SocialFeature
import AIFeature
import ReaderFeature
import QuizFeature
import EngagementFeature
import PaywallFeature
import OnboardingFeature

/// The top-level observable app state that drives `AppRootView`.
///
/// Responsibilities:
/// - Own `AuthService` (Amplify operations) and `SessionManager` (session lifecycle).
/// - Expose `authService` to `AuthFlowView` for the sign-in/sign-up forms.
/// - Track the user's display name resolved from the Cognito id_token JWT.
/// - Own the currently selected tab and per-tab `Router` navigation stacks.
/// - Vend the shared `LibraryRepository` consumed by `HomeView` and `LibraryView`.
/// - Own `EntitlementService` (subscription gating) and `StoreKitService`.
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

    // MARK: - Gift deep-link state

    /// Set when a `chapterflow://gift/{code}` deep link lands; cleared when the
    /// claim sheet is dismissed. `AppRootView` watches this and presents the sheet.
    public var pendingGiftCode: String?

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

    /// Set when the app opens via a `chapterflow://pair/accept/{code}` Universal Link.
    /// ``ProfileView`` reads this to surface the ``AcceptInviteView`` immediately.
    /// Cleared after the sheet is dismissed.
    public var pendingPairAcceptCode: String = ""

    // MARK: - AI

    /// Shared repository for the "Ask the book" feature.
    public let aiRepository: any AIRepository

    // MARK: - Reader / Quiz / Annotation

    /// Shared repository for the reading experience.
    public let readerRepository: any ReaderRepository
    /// Shared repository for chapter quizzes.
    public let quizRepository: any QuizRepository
    /// `nil` when the persistence container couldn't be initialised (edge case).
    public let annotationRepository: (any AnnotationRepository)?

    // MARK: - Reviews

    /// Shared repository for the FSRS spaced-repetition Reviews tab.
    public let reviewsRepository: ReviewsRepository

    // MARK: - Audio

    /// Shared user preferences (persisted to App Group UserDefaults).
    public let preferences: AppPreferences

    /// Shared audio player model — owns the AVQueuePlayer and session for the entire app.
    public let audioPlayerModel: AudioPlayerModel

    // MARK: - Onboarding

    /// Repository driving the first-run onboarding flow.
    public let onboardingRepository: any OnboardingRepository

    // MARK: - Subscription / Paywall

    /// StoreKit 2 service — shared with `EntitlementService` and `PaywallModel`.
    public let storeKitService: StoreKitService

    /// Single source of truth for Pro access throughout the app.
    public let entitlementService: EntitlementService

    /// Whether the paywall sheet is currently presented.
    public var showPaywall: Bool = false

    /// Context that controls the copy shown inside the paywall.
    public var paywallContext: PaywallContext = .settings

    // MARK: - Internal

    /// Retained so `makePaywallModel(context:)` can build `PaywallModel` without re-creating the client.
    private let apiClient: any APIClientProtocol

    // MARK: - Init

    public init(config: AppConfig = .fromInfoPlist()) {
        let svc = AuthService(config: config)
        self.authService = svc
        let sm = SessionManager(authService: svc)
        self.session = sm

        let container = try? PersistenceController.makeDefault().container
        let client = APIClient(config: config, tokenProvider: sm)
        self.apiClient = client
        self.libraryRepository = LiveLibraryRepository(client: client, container: container)
        self.bookDetailRepository = LiveBookDetailRepository(client: client)
        self.socialRepository = LiveSocialRepository(client: client)
        self.aiRepository = LiveAIRepository(client: client)
        self.readerRepository = LiveReaderRepository(client: client)
        self.quizRepository = LiveQuizRepository(client: client)
        if let container {
            self.annotationRepository = LiveAnnotationRepository(container: container, apiClient: client)
        } else {
            self.annotationRepository = nil
        }

        self.reviewsRepository = ReviewsRepository(apiClient: client, modelContainer: container)
        self.onboardingRepository = LiveOnboardingRepository(apiClient: client)

        let prefs = AppPreferences()
        self.preferences = prefs
        let audioRepo = LiveAudioRepository(client: client)
        let audioPlayer = AudioPlayer(repository: audioRepo)
        self.audioPlayerModel = AudioPlayerModel(player: audioPlayer, preferences: prefs)

        let skConfig = StoreKitConfig.from(config)
        let sks = StoreKitService(apiClient: client, config: skConfig)
        self.storeKitService = sks
        self.entitlementService = EntitlementService(storeKitService: sks, apiClient: client)

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

    /// Configures Amplify, starts auth-events listener, and begins entitlement refresh.
    /// Call once at launch.
    public func configure() throws {
        try session.configure()
        entitlementService.start()
    }

    // MARK: - Paywall factory

    /// Creates a fresh `PaywallModel` for the given context.
    /// Called by `AppRootView` each time the paywall sheet is presented.
    public func makePaywallModel(context: PaywallContext) -> PaywallModel {
        PaywallModel(storeKitService: storeKitService, apiClient: apiClient, context: context)
    }

    /// Opens the App Store subscription management page.
    public func openManageSubscriptions() {
        #if canImport(UIKit)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        Task { await UIApplication.shared.open(url) }
        #endif
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
        case .pairAccept(let code):
            pendingPairAcceptCode = code
            selectedTab = .profile
        case .gift(let code):
            selectedTab = .profile
            pendingGiftCode = code
        case .unknown:
            break
        }
    }
}
