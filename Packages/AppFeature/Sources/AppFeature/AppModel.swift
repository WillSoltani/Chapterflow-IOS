// swiftlint:disable file_length
import SwiftUI
import Observation
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

    // MARK: - Focus filter

    /// `true` when a Reading Focus filter is active. Written by `consumeFocusFilter()`
    /// on every foreground activation. `AppRootView` uses this to overlay non-reading tabs.
    public var isReadingFocusActive: Bool = false

    // MARK: - User profile

    /// Display name resolved from the Cognito id_token JWT.
    /// Falls back to `"Reader"` when signed in with no name claims.
    public internal(set) var displayName: String = ""

    // MARK: - Tab selection

    public var selectedTab: AppTab = .home

    // MARK: - Handoff / deep-link reading flow

    /// Set when a Handoff activity should open the reader immediately.
    /// ``AppRootView`` observes this and presents the `ReadingFlowView` full-screen cover.
    /// Cleared by `AppRootView` once consumed.
    /// Internal because `ReadingFlow` is an AppFeature-module type.
    var pendingHandoffFlow: ReadingFlow?

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
    /// Required durable repository for notes, highlights, and bookmarks.
    public let annotationRepository: any AnnotationRepository

    // MARK: - Reviews

    /// Shared repository for the FSRS spaced-repetition Reviews tab.
    public let reviewsRepository: ReviewsRepository

    // MARK: - App Store review

    /// Applies the review-prompt policy and, at a genuine positive moment, asks StoreKit
    /// for an App Store review (see ``AppRootView`` for the trigger call site).
    public let reviewPromptController: ReviewPromptController

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

    // MARK: - Extension inbox

    /// Number of items drained from the extension outbox on the last foreground cycle.
    /// `AppRootView` observes this to show a confirmation banner.
    public var extensionInboxCount: Int = 0

    /// `true` while the "Saved to Notebook" confirmation banner is visible.
    /// Set by ``drainExtensionOutbox()``; cleared by `AppRootView` after the
    /// banner auto-dismisses.
    public var showExtensionInboxBanner: Bool = false

    // MARK: - Mobile config (force-update / maintenance)

    /// Drives the force-update / maintenance gate from `GET /book/config/ios` (B4).
    /// Refreshed at launch and on every foreground; fails open on any error.
    public let appConfigService: AppConfigService

    // MARK: - Reachability

    /// Shared reachability service — consumed by repositories and views.
    public let reachability: ReachabilityService

    // MARK: - Spotlight

    /// Indexes books and chapters into Core Spotlight. Owned here so the app can
    /// clear the index on sign-out regardless of which screen is active.
    let spotlightIndexer = SpotlightIndexer()

    // MARK: - Sync engine (P3.4)

    /// Drains the offline write outbox when connectivity is restored.
    private let syncEngineInternal: SyncEngine

    /// Observable sync status forwarded to the Settings sync section.
    public var syncStatus: SyncStatus? { syncEngineInternal.status }

    // MARK: - Download manager (P3.2 / P3.6)

    private let downloadManagerInternal: DownloadManager
    public var downloadInfoProvider: (any DownloadInfoProviding)? { downloadManagerInternal }

    #if os(iOS)
    let bgSyncCoordinator: BackgroundSyncCoordinator
    #endif

    // MARK: - Analytics & crash reporting

    /// The production analytics sink — shared across all feature models.
    public let analytics: any AnalyticsClient

    /// The crash reporter (Sentry-backed in prod, no-op in debug when DSN is empty).
    public let crashReporter: any CrashReporter

    #if os(iOS)
    private let metricKitSubscriber: MetricKitCrashSubscriber
    #endif

    // MARK: - Internal

    /// Retained so `makePaywallModel(context:)` can build `PaywallModel` without re-creating the client.
    private let apiClient: any APIClientProtocol

    /// Internal only so composition/lifecycle tests can inject closed events.
    /// Diagnostics consumers receive immutable snapshots through the public API.
    let apiObservationHealthRecorder: APIObservationHealthRecorder

    /// Thread-safe store for the current user ID, readable cross-actor.
    /// Written on MainActor when sign-in completes; reads are safe because
    /// String is a value type and the only hazard is a brief sign-in/out race.
    private let userIdBox: UserIdBox

    /// Guards process-long lifecycle hooks from duplicate starts.
    private var didActivateRequiredServices = false
    private var didStartRootServices = false

    // MARK: - Init

    // swiftlint:disable:next function_body_length
    public init(
        config validatedConfig: ValidatedAppConfig,
        persistence: AppPersistenceResources,
        authService: AuthService,
        session: SessionManager
    ) {
        let config = validatedConfig.value
        self.authService = authService
        let sm = session
        self.session = session

        let reporter = CrashReporterFactory.make(
            dsn: config.sentryDSN,
            environment: {
                #if DEBUG
                return "development"
                #else
                return "production"
                #endif
            }()
        )
        self.crashReporter = reporter

        let observationComposition = LiveAPIClientComposition(
            config: config,
            tokenProvider: sm,
            reporter: reporter,
            initialSessionState: Self.apiObservationSessionState(for: session.authState)
        )
        let client = observationComposition.client
        self.apiObservationHealthRecorder = observationComposition.healthRecorder
        self.apiClient = client
        self.appConfigService = AppConfigService(apiClient: client)

        let container = persistence.controller.container

        let analyticsBaseURL = URL(string: config.apiBaseURL) ?? URL(string: "https://api.chapterflow.ca")!
        let analyticsTransport = URLSessionAnalyticsTransport(
            baseURL: analyticsBaseURL,
            tokenProvider: { [sm] in try? await sm.validToken() }
        )
        let analyticsClient = DefaultAnalyticsClient.makeDurable(transport: analyticsTransport)
        self.analytics = analyticsClient

        #if os(iOS)
        let mkSubscriber = MetricKitCrashSubscriber(reporter: reporter, analytics: analyticsClient)
        self.metricKitSubscriber = mkSubscriber
        #endif

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
        self.annotationRepository = LiveAnnotationRepository(container: container, apiClient: client)
        let syncEngine = SyncEngine(apiClient: client, container: container)
        self.syncEngineInternal = syncEngine
        let downloadManager = Self.makeDownloadManager(
            container: container,
            fileStore: persistence.downloadFileStore,
            apiClient: client
        )
        self.downloadManagerInternal = downloadManager

        self.reviewsRepository = ReviewsRepository(apiClient: client, modelContainer: container)
        self.onboardingRepository = LiveOnboardingRepository(apiClient: client)
        self.settingsRepository = LiveSettingsRepository(client: client)

        self.reviewPromptController = ReviewPromptController(
            store: KeyValueReviewPromptVersionStore(),
            currentVersion: Bundle.main.appShortVersion
        )

        let prefs = AppPreferences()
        self.preferences = prefs
        let audioPlayer = AudioPlayer(repository: LiveAudioRepository(client: client))
        self.audioPlayerModel = AudioPlayerModel(player: audioPlayer, preferences: prefs)

        let sks = StoreKitService(apiClient: client, config: StoreKitConfig.from(config))
        self.storeKitService = sks
        self.entitlementService = EntitlementService(storeKitService: sks, apiClient: client)

        #if os(iOS)
        let authorizer: any NotificationAuthorizerProtocol = NotificationAuthorizer()
        #else
        // AppFeature declares macOS only as a SwiftPM build/test host. Apple's
        // process-global notification center traps there because the test
        // runner is not an application bundle, so keep host-only composition
        // inert without changing the shipping iOS graph.
        let authorizer: any NotificationAuthorizerProtocol = HostNotificationAuthorizer()
        #endif
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
        let coordinator = Self.makeCoordinator(
            box: box,
            engine: syncEngine,
            downloadManager: downloadManager,
            entitlementService: self.entitlementService
        )
        self.bgSyncCoordinator = coordinator
        #endif
        #if DEBUG
        applyLaunchArguments()
        #endif
        observeAPIObservationSessionTransitions()
    }

    // MARK: - Lifecycle

    /// Activates process-long services after the graph factory has successfully
    /// configured the required session boundary. Repeated calls are harmless.
    func activateRequiredServices() {
        guard !didActivateRequiredServices else { return }
        didActivateRequiredServices = true
        entitlementService.start()
        #if os(iOS)
        metricKitSubscriber.register()
        session.registerBackgroundRefresh()
        bgSyncCoordinator.registerBackgroundTasks()
        #endif
    }

    /// Starts non-critical root services exactly once after bootstrap publishes
    /// the configured graph.
    public func startRootServices() {
        guard !didStartRootServices else { return }
        didStartRootServices = true
        wirePushRouting()
        Task { await appConfigService.refresh() }
        analytics.track(.appOpen)
        Task(priority: .utility) {
            IntentDonationManager.update()
        }
        Task { await analytics.flush() }
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
            await self?.syncEngineInternal.start(userId: userId)
        }
    }

    /// Signs the user out, unregistering the APNs token from the backend first.
    /// Also removes all Spotlight index entries to honour auth state.
    public func signOut() async {
        apiObservationHealthRecorder.transition(to: .signedOut)
        userIdBox.userId = nil
        await apnsManager.handleSignOut()
        await syncEngineInternal.stop()
        await session.signOut()
        isGuestMode = false
        await spotlightIndexer.removeAll()
    }

    /// Returns only bounded, already-sanitized API health for tests and a later
    /// internal diagnostics surface. No account identifier is retained.
    public func apiObservationHealthSnapshot() -> APIObservationHealthSnapshot {
        apiObservationHealthRecorder.snapshot()
    }

    /// Clears synchronously in Observation's will-change callback, then rearms
    /// against the new auth state on the main actor. Requests started before the
    /// transition carry the older generation and are rejected on completion.
    private func observeAPIObservationSessionTransitions() {
        let recorder = apiObservationHealthRecorder
        withObservationTracking {
            _ = session.authState
        } onChange: { [weak self, recorder] in
            recorder.beginSessionTransition()
            Task { @MainActor [weak self, recorder] in
                guard let self else { return }
                recorder.completeSessionTransition(
                    to: Self.apiObservationSessionState(for: self.session.authState)
                )
                self.observeAPIObservationSessionTransitions()
            }
        }
    }

    private static func apiObservationSessionState(
        for authState: AuthState
    ) -> APIObservationSessionState {
        if case .signedIn = authState {
            .signedIn
        } else {
            .signedOut
        }
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
        PaywallModel(storeKitService: storeKitService, apiClient: apiClient, analytics: analytics, context: context)
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
            // iOS has no deferred deep-link API — a new install cannot carry the
            // code automatically. The Profile tab always shows a manual entry path.
            pendingReferralCode = code
            selectedTab = .profile
        case .paywall:
            paywallContext = .settings
            showPaywall = true
        case .journey, .event:
            // Journey and event detail screens live inside the Engagement/Home tab.
            selectedTab = .home
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
}

#if !os(iOS)
private struct HostNotificationAuthorizer: NotificationAuthorizerProtocol {
    func currentStatus() async -> NotificationPermissionStatus { .denied }

    func requestAuthorization() async -> NotificationAuthorizationOutcome { .denied }

    func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome { .denied }
}
#endif
