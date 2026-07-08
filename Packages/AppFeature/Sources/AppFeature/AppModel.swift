import SwiftUI
import CoreKit
import Models
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
import NotificationsFeature
import OnboardingFeature
import SettingsFeature
import CoreSpotlight
import SyncEngine

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

    // MARK: - Guest browse mode

    /// `true` when the user has chosen to browse without signing in.
    /// `AppRootView` shows the main tab shell (Library/Discover fully public)
    /// while `authState == .signedOut && isGuestMode`.
    public var isGuestMode: Bool = false

    /// Whether the auth gate sheet is currently presented.
    public var showAuthGate: Bool = false

    /// The action a guest was trying to perform when they hit an auth gate.
    /// Cleared and replayed by `replayPendingIntent()` after sign-in.
    public var pendingAuthIntent: AuthGateIntent = .none

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

    // MARK: - Referral deep-link state

    /// Set when a `chapterflow://ref/{code}` deep link lands; cleared after the
    /// enter-code screen is dismissed. Drives pre-filling of ``EnterReferralCodeView``.
    ///
    /// iOS has no deferred deep-link API — a referral link that sends a new user
    /// through an App Store install cannot carry the code into the app automatically.
    /// This property handles the case where the app is already installed and the
    /// link opens it directly. New installs must use the manual entry flow.
    public var pendingReferralCode: String = ""

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

    // MARK: - Settings

    /// Repository for the Settings tab: server reading prefs, export, and account lifecycle.
    public let settingsRepository: any SettingsRepository

    // MARK: - Subscription / Paywall

    /// StoreKit 2 service — shared with `EntitlementService` and `PaywallModel`.
    public let storeKitService: StoreKitService

    /// Single source of truth for Pro access throughout the app.
    public let entitlementService: EntitlementService

    /// Whether the paywall sheet is currently presented.
    public var showPaywall: Bool = false

    /// Context that controls the copy shown inside the paywall.
    public var paywallContext: PaywallContext = .settings

    /// Whether the full subscription management sheet is presented.
    public var showSubscriptionManagement: Bool = false

    // MARK: - Push notifications

    /// Manages APNs token registration with the backend. Observable so
    /// `SettingsView` can display the live push authorization status.
    public let apnsManager: APNSRegistrationManager

    /// Drives the Notification Settings screen. Exposed so `SettingsView` can
    /// pass it to `NotificationSettingsView` as a navigation destination.
    public let notificationSettingsModel: NotificationSettingsModel

    // MARK: - Notification inbox

    /// Drives the in-app notification inbox (P9.4).
    public let notificationInboxModel: NotificationInboxModel

    /// Whether the notification inbox sheet is currently presented.
    public var showNotificationInbox: Bool = false

    // MARK: - Reachability

    /// Shared reachability service — consumed by repositories and views.
    public let reachability: ReachabilityService

    // MARK: - Spotlight

    /// Indexes books and chapters into Core Spotlight. Owned here so the app can
    /// clear the index on sign-out regardless of which screen is active.
    let spotlightIndexer = SpotlightIndexer()

    // MARK: - Sync engine (P3.4)

    /// Drains the offline write outbox when connectivity is restored.
    /// `nil` only when SwiftData couldn't be initialised (edge case).
    private let syncEngineInternal: SyncEngine?

    /// Observable sync status forwarded to the Settings sync section.
    public var syncStatus: SyncStatus? { syncEngineInternal?.status }

    // MARK: - Download manager (P3.2 / P3.6)

    private let downloadManagerInternal: DownloadManager?
    public var downloadInfoProvider: (any DownloadInfoProviding)? { downloadManagerInternal }

    #if os(iOS)
    let bgSyncCoordinator: BackgroundSyncCoordinator
    #endif

    // MARK: - Internal

    /// Retained so `makePaywallModel(context:)` can build `PaywallModel` without re-creating the client.
    private let apiClient: any APIClientProtocol

    /// Thread-safe store for the current user ID, readable cross-actor.
    /// Written on MainActor when sign-in completes; reads are safe because
    /// String is a value type and the only hazard is a brief sign-in/out race.
    private let userIdBox: UserIdBox

    // MARK: - Init

    public init(config: AppConfig = .fromInfoPlist()) {
        let svc = AuthService(config: config)
        self.authService = svc
        let sm = SessionManager(authService: svc)
        self.session = sm

        let container = try? PersistenceController.makeDefault().container
        let client = APIClient(config: config, tokenProvider: sm)
        self.apiClient = client
        let reach = ReachabilityService()
        self.reachability = reach
        let box = UserIdBox()
        self.userIdBox = box
        let userIdClosure: @Sendable () -> String? = { [box] in box.userId }
        self.libraryRepository = LiveLibraryRepository(
            client: client,
            container: container,
            reachability: reach
        )
        self.bookDetailRepository = LiveBookDetailRepository(client: client)
        self.socialRepository = LiveSocialRepository(client: client)
        self.aiRepository = LiveAIRepository(client: client)
        self.readerRepository = LiveReaderRepository(
            client: client,
            container: container,
            reachability: reach,
            userId: userIdClosure
        )
        self.quizRepository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reach,
            userId: userIdClosure
        )
        let engine: SyncEngine?
        let dlManager: DownloadManager?
        if let container {
            self.annotationRepository = LiveAnnotationRepository(container: container, apiClient: client)
            let syncEngine = SyncEngine(apiClient: client, container: container)
            self.syncEngineInternal = syncEngine
            engine = syncEngine
            let dm = Self.makeDownloadManager(container: container, apiClient: client)
            self.downloadManagerInternal = dm
            dlManager = dm
        } else {
            self.annotationRepository = nil
            self.syncEngineInternal = nil
            self.downloadManagerInternal = nil
            engine = nil
            dlManager = nil
        }

        self.reviewsRepository = ReviewsRepository(apiClient: client, modelContainer: container)
        self.onboardingRepository = LiveOnboardingRepository(apiClient: client)
        self.settingsRepository = LiveSettingsRepository(client: client)

        let prefs = AppPreferences()
        self.preferences = prefs
        let audioPlayer = AudioPlayer(repository: LiveAudioRepository(client: client))
        self.audioPlayerModel = AudioPlayerModel(player: audioPlayer, preferences: prefs)

        let sks = StoreKitService(apiClient: client, config: StoreKitConfig.from(config))
        self.storeKitService = sks
        self.entitlementService = EntitlementService(storeKitService: sks, apiClient: client)

        let authorizer = NotificationAuthorizer()
        let registrationRepo = LiveDeviceRegistrationRepository(apiClient: client)
        self.apnsManager = APNSRegistrationManager(authorizer: authorizer, repository: registrationRepo)

        let notifPrefsRepo = LiveNotificationPreferencesRepository(apiClient: client)
        self.notificationSettingsModel = NotificationSettingsModel(
            repository: notifPrefsRepo,
            authorizer: authorizer
        )

        let inboxRepo = LiveNotificationInboxRepository(apiClient: client)
        self.notificationInboxModel = NotificationInboxModel(repository: inboxRepo)

        #if os(iOS)
        sm.registerBackgroundRefresh()
        let coordinator = Self.makeCoordinator(
            box: box, engine: engine, dlManager: dlManager, entSvc: self.entitlementService
        )
        coordinator.registerBackgroundTasks()
        self.bgSyncCoordinator = coordinator
        #endif
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    // MARK: - Lifecycle

    /// Configures Amplify, starts auth-events listener, and begins entitlement refresh.
    /// Call once at launch.
    public func configure() throws {
        try session.configure()
        entitlementService.start()
    }

    /// Starts APNs registration. Call once after `authState` transitions to `.signedIn`.
    public func startAPNS() {
        apnsManager.start()
    }

    /// Starts the offline sync engine for the currently signed-in user.
    /// Call once after `authState` transitions to `.signedIn`.
    public func startSyncEngine() {
        guard case .signedIn(let user) = session.authState else { return }
        let userId = user.userId
        Task { [weak self] in
            await self?.syncEngineInternal?.start(userId: userId)
        }
    }

    /// Signs the user out, unregistering the APNs token from the backend first.
    /// Also removes all Spotlight index entries to honour auth state.
    public func signOut() async {
        userIdBox.userId = nil
        await apnsManager.handleSignOut()
        await syncEngineInternal?.stop()
        await session.signOut()
        isGuestMode = false
        await spotlightIndexer.removeAll()
    }

    // MARK: - Spotlight indexing

    /// Fetches the library catalog and chapter index off the main thread and
    /// submits them to Core Spotlight. Idempotent — safe to call on every sign-in
    /// and whenever the library reloads.
    public func startSpotlightIndexing() {
        let indexer = spotlightIndexer
        let repo = libraryRepository
        Task.detached(priority: .utility) {
            do {
                async let catalogTask = repo.getCatalog()
                async let searchTask = repo.getSearchIndex()
                let (catalog, searchIndex) = try await (catalogTask, searchTask)
                await indexer.index(books: catalog, searchBooks: searchIndex.books)
            } catch {
                // Spotlight indexing is best-effort; never surface errors to the user.
            }
        }
    }

    // MARK: - Guest browse mode

    /// Transitions into guest mode: the user browses the catalog without signing in.
    /// Called from `WelcomeView`'s "Browse without account" button.
    public func enterGuestMode() {
        isGuestMode = true
    }

    /// Captures a gated-action intent and presents the auth gate sheet.
    ///
    /// After the user signs in, `AppRootView` calls `replayPendingIntent()` to
    /// execute the captured action.
    public func requestAuth(intent: AuthGateIntent) {
        pendingAuthIntent = intent
        showAuthGate = true
    }

    /// Executes the pending intent after a successful sign-in.
    ///
    /// Starts the book and opens the reader for `.startBook`, or does nothing
    /// for `.none`. Called from `AppRootView.onChange(of: authState)`.
    func replayPendingIntent(readingFlowSetter: (ReadingFlow) -> Void) async {
        let intent = pendingAuthIntent
        pendingAuthIntent = .none
        isGuestMode = false

        switch intent {
        case .startBook(let bookId, let variantFamily):
            do {
                async let stateTask = bookDetailRepository.startBook(id: bookId)
                let stateResponse = try await stateTask
                let chapterNumber = resolveChapterNumber(from: stateResponse.state)
                readingFlowSetter(ReadingFlow(
                    bookId: bookId,
                    chapterNumber: chapterNumber,
                    variantFamily: variantFamily
                ))
            } catch {
                // If start fails (e.g. no entitlement), just navigate to library so
                // the user can see the book detail with the paywall.
                selectedTab = .library
            }

        case .none:
            break
        }
    }

    private func resolveChapterNumber(from state: BookUserBookState) -> Int {
        guard let chapterId = state.currentChapterId ?? state.lastReadChapterId else { return 1 }
        // Without the manifest in scope here, we fall back to chapter 1. The
        // reader loads its own manifest and handles an invalid chapter number
        // gracefully by opening the first available chapter.
        _ = chapterId
        return 1
    }

    // MARK: - Paywall factory

    /// Creates a fresh `PaywallModel` for the given context.
    /// Called by `AppRootView` each time the paywall sheet is presented.
    public func makePaywallModel(context: PaywallContext) -> PaywallModel {
        PaywallModel(storeKitService: storeKitService, apiClient: apiClient, context: context)
    }

    /// Creates a fresh `SubscriptionManagementModel`.
    /// Called by `AppRootView` when the subscription management sheet is presented.
    public func makeSubscriptionManagementModel() -> SubscriptionManagementModel {
        SubscriptionManagementModel(storeKitService: storeKitService, apiClient: apiClient)
    }

    /// Opens the App Store subscription management page.
    ///
    /// Legacy path; prefer `showSubscriptionManagement = true` to present the
    /// in-app subscription management sheet instead.
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
        // Resolve userId first so repositories can use it immediately.
        if case .signedIn(let user) = session.authState {
            userIdBox.userId = user.userId
        }

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
        // In guest mode, browseable links go through normally;
        // account-only links trigger the auth gate instead.
        if isGuestMode {
            switch deepLink {
            case .book, .chapter, .library:
                selectedTab = .library
            default:
                requestAuth(intent: .none)
            }
            return
        }
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
        case .referral(let code):
            pendingReferralCode = code
            selectedTab = .profile
        case .library:
            selectedTab = .library
        case .profile:
            selectedTab = .profile
        case .engagement:
            selectedTab = .home
        case .notifications:
            selectedTab = .home
            showNotificationInbox = true
        case .unknown:
            break
        }
    }

    // MARK: - Push notification routing

    /// Wires the `PushRoutingBridge` so incoming notification taps are routed
    /// through `handle(url:)`. Call once at app startup (from `AppRootView.task`).
    public func wirePushRouting() {
        #if canImport(UIKit)
        PushRoutingBridge.shared.onNotificationTapped = { [weak self] url in
            self?.handle(url: url)
        }
        #endif
    }

    // MARK: - App Intent integration

    /// Reads a pending audio control command written by P8.2 Live Activity buttons
    /// (``PauseAudioIntent`` / ``ResumeAudioIntent``) via App Group UserDefaults.
    ///
    /// Call when the app becomes active (scenePhase → `.active`) so commands from
    /// Dynamic Island taps are processed even after the app was backgrounded.
    public func consumeAudioControlCommand() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let command = defaults?.string(forKey: IntentKeys.audioControlCommand),
              !command.isEmpty else { return }
        defaults?.removeObject(forKey: IntentKeys.audioControlCommand)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch command {
            case "pause":
                if audioPlayerModel.isPlaying { await audioPlayerModel.togglePlayPause() }
            case "play":
                if !audioPlayerModel.isPlaying, audioPlayerModel.phase != .idle {
                    await audioPlayerModel.togglePlayPause()
                }
            default:
                break
            }
        }
    }

    /// Reads accumulated offline reading minutes written by ``LogDailyReadingIntent``,
    /// adds them to today's goal progress in the App Group snapshot, and publishes.
    ///
    /// Call when the app becomes active so the goal-ring widget reflects minutes
    /// logged via Siri since the last foreground session.
    public func consumePendingReadingMinutes() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let pending = defaults?.integer(forKey: IntentKeys.pendingReadingMinutes) ?? 0
        guard pending > 0 else { return }
        defaults?.removeObject(forKey: IntentKeys.pendingReadingMinutes)
        var updated = SharedStateReader().load()
        updated.goalProgressMinutes += pending
        updated.lastUpdated = Date()
        Task { await SharedStateWriter.shared.publish(updated) }
    }
}
