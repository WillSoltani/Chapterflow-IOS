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
#if os(iOS)
import WidgetKit
#endif

private enum SessionTransitionTarget: Equatable {
    case signedIn(SessionIdentity)
    case signedOut

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.signedOut, .signedOut):
            true
        case (.signedIn(let lhs), .signedIn(let rhs)):
            lhs.subject == rhs.subject
        default:
            false
        }
    }
}

/// One exact external navigation request owned by the application shell.
///
/// This intentionally covers only WP-NAV-01A. Journey and event destinations
/// retain their existing safe tab fallback until WP-NAV-01B owns them.
enum AppNavigationRequest: Sendable, Equatable {
    case book(id: String)
    case chapter(bookId: String, chapter: Int)
    case review
    case pairAccept(code: String)
    case gift(code: String)
    case referral(code: String)
    case notifications
    case paywall

    var requiresActiveScope: Bool {
        if case .book = self { return false }
        return true
    }
}

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

    #if DEBUG
    private static let deferredAuthUITestKey = "CF_UITEST_DEFERRED_AUTH"

    static func isHermeticDeferredAuthUITest(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[deferredAuthUITestKey] == "1"
            && environment["CF_STUB_SERVER"] == "1"
            && environment["CF_HERMETIC_TEST_CONFIGURATION"] == "1"
            && environment["CF_UITEST_BYPASS_AUTH"] != "1"
    }
    #endif

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

    /// The one exact external request waiting for private-scope authority.
    /// Internal so deterministic tests can prove payload and account affinity.
    private(set) var pendingNavigationRequest: AppNavigationRequest?
    private var pendingNavigationAccountID: String?

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

    /// Public-only when signed out; account-scoped when the matching scope is active.
    public var libraryRepository: any LibraryRepository {
        activeGraph?.libraryRepository ?? guestLibraryRepository
    }

    /// Shared repository for the Book Detail screen.
    public var bookDetailRepository: any BookDetailRepository {
        activeGraph?.bookDetailRepository ?? guestBookDetailRepository
    }

    // MARK: - Social

    /// Shared repository for all of Lane S — profile, pairs, gifts, reflections, referrals.
    public var socialRepository: any SocialRepository { requiredGraph.socialRepository }

    /// Set when the app opens via a `chapterflow://pair/accept/{code}` Universal Link.
    /// ``ProfileView`` reads this to surface the ``AcceptInviteView`` immediately.
    /// Cleared after the sheet is dismissed.
    public var pendingPairAcceptCode: String = ""

    // MARK: - AI

    /// Shared repository for the "Ask the book" feature.
    public var aiRepository: any AIRepository { requiredGraph.aiRepository }

    // MARK: - Reader / Quiz / Annotation

    /// Shared repository for the reading experience.
    public var readerRepository: any ReaderRepository { requiredGraph.readerRepository }
    /// Shared repository for chapter quizzes.
    public var quizRepository: any QuizRepository { requiredGraph.quizRepository }
    /// Required durable repository for notes, highlights, and bookmarks.
    public var annotationRepository: any AnnotationRepository { requiredGraph.annotationRepository }

    // MARK: - Reviews

    /// Shared repository for the FSRS spaced-repetition Reviews tab.
    public var reviewsRepository: ReviewsRepository { requiredGraph.reviewsRepository }

    // MARK: - App Store review

    /// Applies the review-prompt policy and, at a genuine positive moment, asks StoreKit
    /// for an App Store review (see ``AppRootView`` for the trigger call site).
    public let reviewPromptController: ReviewPromptController

    // MARK: - Audio

    /// Shared user preferences (persisted to App Group UserDefaults).
    public var preferences: AppPreferences { requiredGraph.preferences }

    /// Lightweight account-scoped state used by search, book preferences, and reader resume.
    var keyValueStore: KeyValueStore { requiredGraph.keyValueStore }
    var workPermit: SessionWorkPermit { requiredGraph.permit }
    var dailyGoalStore: DailyGoalStore { requiredGraph.dailyGoalStore }

    /// Explicitly public guest state; never reads historical unprefixed account keys.
    var guestKeyValueStore: KeyValueStore { guestPresentationStores.keyValueStore }
    var guestPreferences: AppPreferences { guestPresentationStores.preferences }

    /// Shared audio player model — owns the AVQueuePlayer and session for the entire app.
    public var audioPlayerModel: AudioPlayerModel { requiredGraph.audioPlayerModel }

    // MARK: - Onboarding

    /// Repository driving the first-run onboarding flow.
    public var onboardingRepository: any OnboardingRepository { requiredGraph.onboardingRepository }

    // MARK: - Settings

    /// Repository for the Settings tab: server reading prefs, export, and account lifecycle.
    public var settingsRepository: any SettingsRepository { requiredGraph.settingsRepository }

    // MARK: - Subscription / Paywall

    /// StoreKit 2 service — shared with `EntitlementService` and `PaywallModel`.
    public var storeKitService: StoreKitService { requiredGraph.storeKitService }

    /// Single source of truth for Pro access throughout the app.
    public var entitlementService: EntitlementService { requiredGraph.entitlementService }

    /// Whether the paywall sheet is currently presented.
    public var showPaywall: Bool = false

    /// Context that controls the copy shown inside the paywall.
    public var paywallContext: PaywallContext = .settings

    /// Whether the full subscription management sheet is presented.
    public var showSubscriptionManagement: Bool = false

    // MARK: - Push notifications

    /// Manages APNs token registration with the backend. Observable so
    /// `SettingsView` can display the live push authorization status.
    public var apnsManager: APNSRegistrationManager { requiredGraph.apnsManager }

    /// Drives the Notification Settings screen. Exposed so `SettingsView` can
    /// pass it to `NotificationSettingsView` as a navigation destination.
    public var notificationSettingsModel: NotificationSettingsModel {
        requiredGraph.notificationSettingsModel
    }

    // MARK: - Notification inbox

    /// Drives the in-app notification inbox (P9.4).
    public var notificationInboxModel: NotificationInboxModel { requiredGraph.notificationInboxModel }

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
    private var spotlightIndexTask: Task<Void, Never>?
    private var spotlightIndexTaskID: UUID?

    // MARK: - Sync engine (P3.4)

    /// Drains the offline write outbox when connectivity is restored.
    /// Observable sync status forwarded to the Settings sync section.
    public var syncStatus: SyncStatus? { activeGraph?.syncEngine.status }

    // MARK: - Download manager (P3.2 / P3.6)

    public var downloadInfoProvider: (any DownloadInfoProviding)? {
        activeGraph?.downloadManager
    }

    /// The active account identity used by account-bound UI collaborators.
    /// Access is valid only while the root is rendering the active private shell.
    var activeAccountID: String { requiredGraph.context.accountID }

    /// Full immutable authority passed only to private collaborators that require it.
    var activeAccountContext: AccountContext { requiredGraph.context }

    /// The active account's download coordinator. Guest/public UI never receives it.
    var activeDownloadManager: DownloadManager { requiredGraph.downloadManager }

    #if os(iOS)
    let bgSyncCoordinator: BackgroundSyncCoordinator
    #endif

    // MARK: - Analytics & crash reporting

    /// The production analytics sink — shared across all feature models.
    public var analytics: any AnalyticsClient {
        activeGraph?.analytics ?? processAnalytics
    }

    /// The crash reporter (Sentry-backed in prod, no-op in debug when DSN is empty).
    public let crashReporter: any CrashReporter

    #if os(iOS)
    private let metricKitSubscriber: MetricKitCrashSubscriber
    #endif

    // MARK: - Internal

    /// Internal only so composition/lifecycle tests can inject closed events.
    /// Diagnostics consumers receive immutable snapshots through the public API.
    let apiObservationHealthRecorder: APIObservationHealthRecorder

    private let validatedConfig: ValidatedAppConfig
    private let accountPersistenceLoader: any AccountPersistenceLoading
    private let guestLibraryRepository: any LibraryRepository
    private let guestBookDetailRepository: any BookDetailRepository
    private let guestPresentationStores = SessionPresentationStores.guest()
    /// Process-owned cancellation gate for public guest presentation work.
    /// It carries no account identity, namespace, or private graph capability.
    let guestWorkPermit = SessionWorkPermit()
    private let processAnalytics: any AnalyticsClient
    private let backgroundWorkBroker: SessionBackgroundWorkBroker
    private let scopeBuilder: @MainActor (AccountContext) async throws -> SessionScope
    private let sessionFeatureModelsBuilder:
        @MainActor (SessionScope, AppModel) -> SessionFeatureModels

    private(set) var activeSessionScope: SessionScope?
    private var sessionFeatureModelsStorage: SessionFeatureModels?
    private(set) var sessionScopePhase: SessionScopePhase = .none
    private var sessionTransitionTask: Task<Void, Never>?
    private var sessionTransitionTarget: SessionTransitionTarget?
    private var sessionTransitionID: UUID?
    private var sessionPreparationGeneration: UInt64 = 0
    private var signOutTask: Task<Bool, Never>?
    private(set) var isCoordinatingSignOut = false
    public private(set) var showsSignOutFailure = false

    /// Authentication entry must stay closed until every A-owned scope has
    /// finished teardown. `SessionManager` may publish `.signedOut` before the
    /// app-level transaction or an auth-observer transition has completed.
    var canPresentSignedOutEntry: Bool {
        session.authState == .signedOut
            && !isCoordinatingSignOut
            && sessionScopePhase == .none
            && activeSessionScope == nil
    }

    /// Guards process-long lifecycle hooks from duplicate starts.
    private var didActivateRequiredServices = false
    private var didStartRootServices = false

    // MARK: - Init

    public convenience init(
        config: ValidatedAppConfig,
        persistence: AppPersistenceResources,
        authService: AuthService,
        session: SessionManager
    ) {
        self.init(
            config: config,
            persistence: persistence,
            authService: authService,
            session: session,
            accountPersistenceLoader: DefaultAccountPersistenceLoader(),
            scopeBuilder: nil,
            sessionFeatureModelsBuilder: nil
        )
    }

    init(
        config validatedConfig: ValidatedAppConfig,
        persistence: AppPersistenceResources,
        authService: AuthService,
        session: SessionManager,
        accountPersistenceLoader: any AccountPersistenceLoading,
        scopeBuilder injectedScopeBuilder: (@MainActor (AccountContext) async throws -> SessionScope)?,
        sessionFeatureModelsBuilder injectedSessionFeatureModelsBuilder:
            (@MainActor (SessionScope, AppModel) -> SessionFeatureModels)? = nil
    ) {
        let config = validatedConfig.value
        self.validatedConfig = validatedConfig
        self.accountPersistenceLoader = accountPersistenceLoader
        self.authService = authService
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
        crashReporter = reporter

        let observationComposition = LiveAPIClientComposition(
            config: config,
            tokenProvider: session,
            reporter: reporter,
            initialSessionState: Self.apiObservationSessionState(for: session.authState)
        )
        let client = observationComposition.client
        apiObservationHealthRecorder = observationComposition.healthRecorder
        appConfigService = AppConfigService(apiClient: client)

        let reachability = ReachabilityService()
        self.reachability = reachability
        let publicRepository = LiveLibraryRepository(
            client: client,
            container: persistence.controller.container,
            reachability: reachability
        )
        guestLibraryRepository = GuestPublicLibraryRepository(base: publicRepository)
        guestBookDetailRepository = GuestPublicBookDetailRepository(
            base: LiveBookDetailRepository(client: client)
        )
        processAnalytics = NoopAnalyticsClient()

        reviewPromptController = ReviewPromptController(
            store: KeyValueReviewPromptVersionStore(),
            currentVersion: Bundle.main.appShortVersion
        )

        let broker = SessionBackgroundWorkBroker()
        backgroundWorkBroker = broker
        let factory = DefaultSessionScopeFactory(
            config: validatedConfig,
            apiClientFactory: observationComposition.clientFactory,
            session: session,
            persistenceLoader: accountPersistenceLoader,
            reachability: reachability,
            backgroundBroker: broker
        )
        scopeBuilder = injectedScopeBuilder ?? { context in
            try await factory.make(context: context)
        }
        sessionFeatureModelsBuilder = injectedSessionFeatureModelsBuilder ?? { scope, model in
            guard let graph = scope.graph else {
                preconditionFailure("Active production scope must publish its private graph")
            }
            return SessionFeatureModels(
                scopeID: scope.context.instanceID,
                graph: graph,
                onSignOut: { [weak model] in await model?.signOut() }
            )
        }

        #if os(iOS)
        metricKitSubscriber = MetricKitCrashSubscriber(
            reporter: reporter,
            analytics: NoopAnalyticsClient()
        )
        bgSyncCoordinator = Self.makeCoordinator(broker: broker)
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
        #if os(iOS)
        metricKitSubscriber.register()
        session.registerBackgroundRefresh()
        bgSyncCoordinator.registerBackgroundTasks()
        #endif
        Task { [weak self] in await self?.reconcileCurrentSession() }
    }

    /// Starts non-critical root services exactly once after bootstrap publishes
    /// the configured graph.
    public func startRootServices() {
        guard !didStartRootServices else { return }
        didStartRootServices = true
        wirePushRouting()
        Task { await appConfigService.refresh() }
        Task(priority: .utility) {
            IntentDonationManager.update()
        }
    }

    /// Runs one idempotent reversible sign-out transaction.
    public func signOut() async {
        if session.authState == .signedOut, activeSessionScope == nil,
           sessionTransitionTask == nil {
            sessionFeatureModelsStorage = nil
            showsSignOutFailure = false
            apiObservationHealthRecorder.transition(to: .signedOut)
            isGuestMode = false
            clearAccountPresentationState()
            return
        }
        if let signOutTask {
            _ = await signOutTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            await self?.performSignOutTransaction() ?? false
        }
        signOutTask = task
        _ = await task.value
        signOutTask = nil
    }

    private func performSignOutTransaction() async -> Bool {
        guard !isCoordinatingSignOut else { return false }
        showsSignOutFailure = false
        isCoordinatingSignOut = true
        defer { isCoordinatingSignOut = false }

        await cancelSessionTransition()
        await cancelSpotlightIndexing()
        await cancelAccountBackgroundWork()
        let scope = activeSessionScope
        if let scope {
            sessionScopePhase = .quiescing
            await scope.quiesce()
        }

        let succeeded = await session.signOut()
        if succeeded {
            apiObservationHealthRecorder.transition(to: .signedOut)
            sessionFeatureModelsStorage = nil
            if let scope { await scope.invalidate() }
            activeSessionScope = nil
            sessionScopePhase = .none
            displayName = ""
            isGuestMode = false
            showAuthGate = false
            clearAccountPresentationState()
            await spotlightIndexer.removeAll()
        } else if let scope {
            await scope.resume()
            activeSessionScope = scope
            sessionScopePhase = .active
            showsSignOutFailure = true
            startSpotlightIndexing()
        } else {
            sessionScopePhase = .none
            showsSignOutFailure = true
        }
        return succeeded
    }

    public func dismissSignOutFailure() {
        showsSignOutFailure = false
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
                await self.reconcileCurrentSession()
            }
        }
    }

    /// Deterministic test seam and the sole auth-observer reconciliation path.
    func reconcileCurrentSession() async {
        guard !isCoordinatingSignOut else { return }
        let target: SessionTransitionTarget
        switch session.authState {
        case .signedIn(let identity):
            let context = AccountContext(identity: identity, config: validatedConfig)
            if let activeMatchingScope,
               activeMatchingScope.context.accountID == context.accountID,
               activeMatchingScope.context.environmentNamespace == context.environmentNamespace,
               sessionTransitionTask == nil {
                installSessionFeatureModels(for: activeMatchingScope)
                sessionScopePhase = .active
                return
            }
            target = .signedIn(identity)
        case .signedOut:
            if canPresentSignedOutEntry,
               sessionTransitionTask == nil,
               sessionTransitionTarget == nil,
               sessionTransitionID == nil {
                return
            }
            target = .signedOut
        case .unknown, .reauthRequired, .reconnecting:
            return
        }

        if let task = sessionTransitionTask, sessionTransitionTarget == target {
            await task.value
            return
        }
        if sessionTransitionTask != nil {
            await cancelSessionTransition()
        }
        guard !isCoordinatingSignOut else { return }

        sessionPreparationGeneration &+= 1
        let generation = sessionPreparationGeneration
        let transitionID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSessionTransition(target, generation: generation)
            self.finishSessionTransition(transitionID)
        }
        sessionTransitionID = transitionID
        sessionTransitionTarget = target
        sessionTransitionTask = task
        await task.value
    }

    private func performSessionTransition(
        _ target: SessionTransitionTarget,
        generation: UInt64
    ) async {
        switch target {
        case .signedIn(let identity):
            await prepareScope(for: identity, generation: generation)
        case .signedOut:
            await tearDownForAuthoritativeSignedOut()
        }
    }

    private func prepareScope(for identity: SessionIdentity, generation: UInt64) async {
        bindPendingNavigationRequest(to: identity.subject)
        let context = AccountContext(identity: identity, config: validatedConfig)
        if let activeSessionScope,
           activeSessionScope.context.accountID == context.accountID,
           activeSessionScope.context.environmentNamespace == context.environmentNamespace,
           activeSessionScope.state == .active,
           sessionCanPublish(context, generation: generation) {
            installSessionFeatureModels(for: activeSessionScope)
            sessionScopePhase = .active
            return
        }

        if let oldScope = activeSessionScope {
            let preservesPendingNavigation = oldScope.context.accountID == context.accountID
            sessionScopePhase = .quiescing
            activeSessionScope = nil
            sessionFeatureModelsStorage = nil
            await cancelSpotlightIndexingAndRemoveAll()
            await cancelAccountBackgroundWork()
            await oldScope.invalidate()
            clearAccountPresentationState(
                preservingPendingNavigation: preservesPendingNavigation
            )

            // A production SessionManager requires A's sign-out transaction to
            // finish before B can authenticate. If an unsupported/test-only
            // identity replacement bypasses that boundary, fail closed instead
            // of constructing B after A's authenticated teardown opportunity is
            // already gone.
            guard oldScope.context.accountID == context.accountID else {
                sessionScopePhase = .failure
                return
            }
        }

        guard sessionCanPublish(context, generation: generation) else {
            sessionScopePhase = .none
            return
        }
        sessionScopePhase = .preparing
        let builder = scopeBuilder

        do {
            let scope = try await builder(context)
            guard sessionCanPublish(context, generation: generation) else {
                await scope.invalidate()
                if generation == sessionPreparationGeneration { sessionScopePhase = .none }
                return
            }
            await scope.activate()
            guard sessionCanPublish(context, generation: generation),
                  scope.state == .active else {
                await scope.invalidate()
                if generation == sessionPreparationGeneration { sessionScopePhase = .none }
                return
            }
            activeSessionScope = scope
            installSessionFeatureModels(for: scope)
            #if DEBUG
            if Self.isHermeticDeferredAuthUITest() {
                scope.graph?.preferences.onboardingCompleted = true
            }
            #endif
            sessionScopePhase = .active
            hydrateDisplayName()
            showAuthGate = false
            isGuestMode = false
            scope.graph?.analytics.track(.appOpen)
            startSpotlightIndexing()
        } catch is CancellationError {
            if generation == sessionPreparationGeneration {
                sessionScopePhase = .none
            }
        } catch {
            if generation == sessionPreparationGeneration {
                activeSessionScope = nil
                sessionFeatureModelsStorage = nil
                // The Recovery retry is still bound to this same proven
                // identity, so preserve its exact request until retry,
                // cancellation, sign-out, or an account mismatch.
                clearAccountPresentationState(preservingPendingNavigation: true)
                sessionScopePhase = .failure
            }
        }
    }

    private func cancelSessionTransition() async {
        guard let task = sessionTransitionTask else { return }
        sessionPreparationGeneration &+= 1
        task.cancel()
        await task.value
    }

    private func finishSessionTransition(_ transitionID: UUID) {
        guard sessionTransitionID == transitionID else { return }
        sessionTransitionTask = nil
        sessionTransitionTarget = nil
        sessionTransitionID = nil
    }

    private func sessionCanPublish(
        _ context: AccountContext,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && generation == sessionPreparationGeneration
            && !isCoordinatingSignOut
            && session.currentIdentity?.subject == context.accountID
    }

    private func tearDownForAuthoritativeSignedOut() async {
        let scope = activeSessionScope
        activeSessionScope = nil
        sessionFeatureModelsStorage = nil
        sessionScopePhase = .quiescing
        await cancelSpotlightIndexingAndRemoveAll()
        await cancelAccountBackgroundWork()
        if let scope {
            await scope.invalidate()
        }
        sessionScopePhase = .none
        displayName = ""
        clearAccountPresentationState()
    }

    private func clearAccountPresentationState(
        preservingPendingNavigation: Bool = false
    ) {
        pendingHandoffFlow = nil
        if !preservingPendingNavigation {
            pendingNavigationRequest = nil
            pendingNavigationAccountID = nil
        }
        pendingGiftCode = nil
        pendingReferralCode = ""
        pendingPairAcceptCode = ""
        showPaywall = false
        showSubscriptionManagement = false
        showNotificationInbox = false
        pendingAuthIntent = .none
        showAuthGate = false
        showsSignOutFailure = false
        extensionInboxCount = 0
        showExtensionInboxBanner = false
        IntentActionStore.shared.pendingDeepLink = nil
        IntentActionStore.shared.pendingAudioPlay = nil
        #if canImport(UIKit)
        QuickActionBridge.shared.pendingShortcutType = nil
        #endif
        #if os(iOS)
        // WidgetKit may otherwise keep an already-materialized A timeline or
        // control value visible after the app has closed A's presentation gate.
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
        homeRouter.popToRoot()
        libraryRouter.popToRoot()
        reviewsRouter.popToRoot()
        profileRouter.popToRoot()
        settingsRouter.popToRoot()
        selectedTab = .home
    }

    private func cancelAccountBackgroundWork() async {
        #if os(iOS)
        await bgSyncCoordinator.cancelActiveWork()
        #endif
    }

    /// The sole private-presentation authority. Auth state and the immutable
    /// scope context must agree synchronously; deferred reconciliation is never
    /// allowed to keep vending the prior account's graph.
    private var activeMatchingScope: SessionScope? {
        guard sessionScopePhase == .active,
              let scope = activeSessionScope,
              scope.state == .active,
              let identity = session.currentIdentity else {
            return nil
        }
        switch session.authState {
        case .signedIn(let signedInIdentity):
            guard signedInIdentity.subject == identity.subject else { return nil }
        case .reauthRequired, .reconnecting:
            break
        case .unknown, .signedOut:
            return nil
        }
        let currentContext = AccountContext(identity: identity, config: validatedConfig)
        guard scope.context.accountID == currentContext.accountID,
              scope.context.environmentNamespace == currentContext.environmentNamespace else {
            return nil
        }
        return scope
    }

    private var activeGraph: SessionPrivateGraph? {
        activeMatchingScope?.graph
    }

    var hasActiveMatchingSessionScope: Bool {
        activeMatchingScope != nil
    }

    var activeScopeInstanceID: UUID? {
        activeMatchingScope?.context.instanceID
    }

    /// The active scope's stable feature-model owner, or `nil` when private
    /// presentation authority is closed or the stored generation is stale.
    var activeSessionFeatureModels: SessionFeatureModels? {
        guard let activeScopeInstanceID,
              sessionFeatureModelsStorage?.scopeID == activeScopeInstanceID else {
            return nil
        }
        return sessionFeatureModelsStorage
    }

    var requiredSessionFeatureModels: SessionFeatureModels {
        guard let activeSessionFeatureModels else {
            preconditionFailure(
                "Session feature model requested without an active matching session scope"
            )
        }
        return activeSessionFeatureModels
    }

    private func installSessionFeatureModels(for scope: SessionScope) {
        guard sessionFeatureModelsStorage?.scopeID != scope.context.instanceID else { return }
        sessionFeatureModelsStorage = sessionFeatureModelsBuilder(scope, self)
    }

    private var requiredGraph: SessionPrivateGraph {
        guard let graph = activeGraph else {
            preconditionFailure("Account-private dependency requested without an active matching session scope")
        }
        return graph
    }

    var activeAudioPlayerModel: AudioPlayerModel? {
        activeGraph?.audioPlayerModel
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
        guard let scope = activeMatchingScope,
              let repo = scope.graph?.libraryRepository else {
            return
        }
        spotlightIndexTask?.cancel()
        let indexer = spotlightIndexer
        let scopeID = scope.context.instanceID
        let taskID = UUID()
        spotlightIndexTaskID = taskID
        let task = Task(priority: .utility) { [weak self] in
            defer { self?.finishSpotlightIndexing(taskID) }
            do {
                async let catalogTask = repo.getCatalog()
                async let searchTask = repo.getSearchIndex()
                let (catalog, searchIndex) = try await (catalogTask, searchTask)
                try Task.checkCancellation()
                guard self?.activeScopeInstanceID == scopeID else { return }
                await indexer.index(books: catalog, searchBooks: searchIndex.books)
            } catch {
                // Spotlight indexing is best-effort; never surface errors to the user.
            }
        }
        spotlightIndexTask = task
    }

    private func finishSpotlightIndexing(_ taskID: UUID) {
        guard spotlightIndexTaskID == taskID else { return }
        spotlightIndexTask = nil
        spotlightIndexTaskID = nil
    }

    private func cancelSpotlightIndexing() async {
        guard let task = spotlightIndexTask else { return }
        spotlightIndexTask = nil
        spotlightIndexTaskID = nil
        task.cancel()
        await task.value
    }

    private func cancelSpotlightIndexingAndRemoveAll() async {
        await cancelSpotlightIndexing()
        await spotlightIndexer.removeAll()
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
        // One actionable request owns the auth transition. A later tap may
        // keep the sheet visible, but cannot overwrite an exact external route.
        guard pendingNavigationRequest == nil else {
            showAuthGate = true
            return
        }
        guard pendingAuthIntent.isNone || pendingAuthIntent == intent else {
            showAuthGate = true
            return
        }
        pendingAuthIntent = intent
        showAuthGate = true
    }

    /// Explicit user cancellation is the only pre-consumption path that drops
    /// an exact pending route.
    public func cancelPendingAuthNavigation() {
        pendingNavigationRequest = nil
        pendingNavigationAccountID = nil
        pendingAuthIntent = .none
        showAuthGate = false
    }

    /// Executes the pending intent after a successful sign-in.
    ///
    /// Starts the book and opens the reader for `.startBook`, or does nothing
    /// for `.none`. Called from `AppRootView.onChange(of: authState)`.
    func replayPendingIntent(readingFlowSetter: (ReadingFlow) -> Void) async {
        guard activeMatchingScope != nil else { return }
        let intent = pendingAuthIntent

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
        pendingAuthIntent = .none
        isGuestMode = false
    }

    /// Replays one exact external route after the matching account scope is
    /// active. The request remains pending if authority is not yet available.
    func replayPendingNavigationRequest() {
        guard let request = pendingNavigationRequest,
              request.requiresActiveScope,
              let scope = activeMatchingScope else {
            return
        }
        if let pendingNavigationAccountID,
           pendingNavigationAccountID != scope.context.accountID {
            cancelPendingAuthNavigation()
            return
        }

        consumeNavigationRequest(request)
        pendingNavigationRequest = nil
        pendingNavigationAccountID = nil
        showAuthGate = false
        isGuestMode = false
    }

    private func bindPendingNavigationRequest(to accountID: String) {
        guard pendingNavigationRequest != nil else { return }
        guard let pendingNavigationAccountID else {
            self.pendingNavigationAccountID = accountID
            return
        }
        guard pendingNavigationAccountID == accountID else {
            cancelPendingAuthNavigation()
            return
        }
    }

    private func enqueuePrivateNavigationRequest(_ request: AppNavigationRequest) {
        guard request.requiresActiveScope else {
            consumeNavigationRequest(request)
            return
        }
        if activeMatchingScope != nil {
            consumeNavigationRequest(request)
            return
        }

        // First request wins until consumption or explicit cancellation.
        if let pendingNavigationRequest {
            if pendingNavigationRequest == request { showAuthGate = true }
            return
        }
        guard pendingAuthIntent.isNone else { return }

        pendingNavigationRequest = request
        pendingNavigationAccountID = session.currentIdentity?.subject
        switch session.authState {
        case .unknown, .signedOut:
            isGuestMode = true
        case .signedIn, .reauthRequired, .reconnecting:
            break
        }
        showAuthGate = true
    }

    private func consumeNavigationRequest(_ request: AppNavigationRequest) {
        switch request {
        case .book(let id):
            selectedTab = .library
            libraryRouter.popToRoot()
            libraryRouter.push(LibraryRoute.bookDetail(bookId: id))
        case .chapter(let bookId, let chapter):
            selectedTab = .library
            let flow = ReadingFlow(
                bookId: bookId,
                chapterNumber: chapter,
                variantFamily: .emh
            )
            if pendingHandoffFlow != flow { pendingHandoffFlow = flow }
        case .review:
            selectedTab = .reviews
        case .pairAccept(let code):
            pendingPairAcceptCode = code
            selectedTab = .profile
        case .gift(let code):
            pendingGiftCode = code
            selectedTab = .profile
        case .referral(let code):
            pendingReferralCode = code
            selectedTab = .profile
        case .notifications:
            selectedTab = .home
            showNotificationInbox = true
        case .paywall:
            paywallContext = .settings
            showPaywall = true
        }
    }

    #if DEBUG
    var canCompleteDeferredHermeticAuth: Bool {
        Self.isHermeticDeferredAuthUITest() && session.authState == .signedOut
    }

    @discardableResult
    func completeDeferredHermeticSignIn() -> Bool {
        guard canCompleteDeferredHermeticAuth,
              let identity = SessionIdentity(
                subject: "uitest-user-123",
                username: "Test User",
                email: nil,
                source: .hermeticUITest
              ) else {
            return false
        }
        let tokens = StoredTokens(
            idToken: "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1aXRlc3QtdXNlci0xMjMiLCJuYW1lIjoiVGVzdCBVc2VyIiwiZXhwIjo5OTk5OTk5OTk5fQ.",
            accessToken: "hermetic-access-token",
            refreshToken: "hermetic-refresh-token",
            expiresAt: .distantFuture
        )
        do {
            try session.establishHermeticSession(identity: identity, tokens: tokens)
            return true
        } catch {
            return false
        }
    }
    #endif

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
        let graph = requiredGraph
        return PaywallModel(
            storeKitService: graph.storeKitService,
            apiClient: graph.apiClient,
            analytics: graph.analytics,
            context: context
        )
    }

    /// Creates a fresh `SubscriptionManagementModel`.
    /// Called by `AppRootView` when the subscription management sheet is presented.
    public func makeSubscriptionManagementModel() -> SubscriptionManagementModel {
        let graph = requiredGraph
        return SubscriptionManagementModel(
            storeKitService: graph.storeKitService,
            apiClient: graph.apiClient
        )
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
        // 1. JWT claims (Cognito stores the name attribute).
        if let token = session.currentIdToken(),
           let profile = UserProfile.from(idToken: token),
           !profile.displayName.isEmpty {
            displayName = profile.displayName
            return
        }
        // 2. Optional display username from the verified Cognito identity.
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
        if let request = navigationRequest(from: deepLink) {
            if request.requiresActiveScope {
                enqueuePrivateNavigationRequest(request)
            } else {
                if activeMatchingScope == nil { isGuestMode = true }
                consumeNavigationRequest(request)
            }
            return
        }

        // WP-NAV-01B owns exact journey/event and external-source routing.
        // Preserve the existing safe tab fallback without inventing a detail.
        switch deepLink {
        case .journey, .event:
            if activeMatchingScope != nil {
                selectedTab = .home
            } else {
                requestAuth(intent: .none)
            }
        case .library:
            if activeMatchingScope == nil { isGuestMode = true }
            selectedTab = .library
        case .profile:
            if activeMatchingScope != nil {
                selectedTab = .profile
            } else {
                requestAuth(intent: .none)
            }
        case .engagement:
            if activeMatchingScope != nil {
                selectedTab = .home
            } else {
                requestAuth(intent: .none)
            }
        case .book, .chapter, .review, .pairAccept, .gift, .referral,
             .notifications, .paywall, .unknown:
            break
        }
    }

    private func navigationRequest(from deepLink: DeepLink) -> AppNavigationRequest? {
        switch deepLink {
        case .book(let id) where Self.isValidRouteValue(id):
            .book(id: id)
        case .chapter(let bookId, let chapter)
            where Self.isValidRouteValue(bookId) && chapter > 0:
            .chapter(bookId: bookId, chapter: chapter)
        case .review:
            .review
        case .pairAccept(let code) where Self.isValidRouteValue(code):
            .pairAccept(code: code)
        case .gift(let code) where Self.isValidRouteValue(code):
            .gift(code: code)
        case .referral(let code) where Self.isValidRouteValue(code):
            .referral(code: code)
        case .notifications:
            .notifications
        case .paywall:
            .paywall
        default:
            nil
        }
    }

    private static func isValidRouteValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
