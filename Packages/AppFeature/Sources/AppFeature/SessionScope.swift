import AIFeature
import AuthKit
import CoreKit
import EngagementFeature
import Foundation
import LibraryFeature
import Networking
import NotificationsFeature
import OnboardingFeature
import PaywallFeature
import Persistence
import QuizFeature
import ReaderFeature
import SettingsFeature
import SocialFeature
import SyncEngine

enum SessionScopeState: Sendable, Equatable {
    case constructed
    case active
    case quiesced
    case invalidated
}

enum SessionScopePhase: Sendable, Equatable {
    case none
    case preparing
    case active
    case failure
    case quiescing
}

struct SessionScopeOperations: Sendable {
    let activate: @MainActor @Sendable () async -> Void
    let quiesce: @MainActor @Sendable () async -> Void
    let resume: @MainActor @Sendable () async -> Void
    let invalidate: @MainActor @Sendable () async -> Void

    static let inert = SessionScopeOperations(
        activate: {},
        quiesce: {},
        resume: {},
        invalidate: {}
    )
}

/// The single lifetime owner for one authenticated account graph.
@MainActor
final class SessionScope {
    let context: AccountContext
    let permit: SessionWorkPermit
    let graph: SessionPrivateGraph?
    private let operations: SessionScopeOperations
    private(set) var state: SessionScopeState = .constructed

    init(
        context: AccountContext,
        permit: SessionWorkPermit = SessionWorkPermit(),
        graph: SessionPrivateGraph? = nil,
        operations: SessionScopeOperations = .inert
    ) {
        self.context = context
        self.permit = permit
        self.graph = graph
        self.operations = operations
    }

    func activate() async {
        guard state == .constructed else { return }
        await operations.activate()
        guard state == .constructed else { return }
        state = .active
    }

    func quiesce() async {
        guard state == .active else { return }
        state = .quiesced
        permit.quiesce()
        await operations.quiesce()
    }

    func resume() async {
        guard state == .quiesced else { return }
        permit.resume()
        await operations.resume()
        guard state == .quiesced else { return }
        state = .active
    }

    func invalidate() async {
        guard state != .invalidated else { return }
        state = .invalidated
        permit.invalidate()
        await operations.invalidate()
    }
}

struct SessionBackgroundWork: Sendable {
    let scopeID: UUID
    let refresh: @Sendable () async -> Void
    let processing: @Sendable () async -> Void
}

actor SessionBackgroundWorkBroker {
    private var work: SessionBackgroundWork?

    func install(_ work: SessionBackgroundWork) {
        self.work = work
    }

    func remove(scopeID: UUID) {
        guard work?.scopeID == scopeID else { return }
        work = nil
    }

    func runRefresh() async {
        guard let work else { return }
        await work.refresh()
    }

    func runProcessing() async {
        guard let work else { return }
        await work.processing()
    }

    var hasActiveScope: Bool { work != nil }
}

/// Lightweight presentation state with one explicit owner namespace.
///
/// Account stores use only the opaque namespace derived by `AccountContext`.
/// Guest state has a separate public namespace and never falls back to the
/// historical unprefixed keys that may contain a prior account's data.
@MainActor
struct SessionPresentationStores {
    let keyValueStore: KeyValueStore
    let preferences: AppPreferences
    let dailyGoalStore: DailyGoalStore

    static func account(
        context: AccountContext,
        defaults: UserDefaults? = nil
    ) -> SessionPresentationStores {
        make(prefix: "account.\(context.storageNamespace).", defaults: defaults)
    }

    static func guest(defaults: UserDefaults? = nil) -> SessionPresentationStores {
        make(prefix: "guest.", defaults: defaults)
    }

    private static func make(
        prefix: String,
        defaults: UserDefaults?
    ) -> SessionPresentationStores {
        SessionPresentationStores(
            keyValueStore: KeyValueStore(defaults: defaults, keyPrefix: prefix),
            preferences: AppPreferences(defaults: defaults, keyPrefix: prefix),
            dailyGoalStore: DailyGoalStore(defaults: defaults, keyPrefix: prefix)
        )
    }
}

@MainActor
final class SessionPrivateGraph {
    let context: AccountContext
    let apiClient: any APIClientProtocol
    let persistence: AccountPersistenceResources
    let libraryRepository: any LibraryRepository
    let bookDetailRepository: any BookDetailRepository
    let socialRepository: any SocialRepository
    let aiRepository: any AIRepository
    let readerRepository: any ReaderRepository
    let quizRepository: any QuizRepository
    let annotationRepository: any AnnotationRepository
    let reviewsRepository: ReviewsRepository
    let keyValueStore: KeyValueStore
    let preferences: AppPreferences
    let dailyGoalStore: DailyGoalStore
    let audioPlayerModel: AudioPlayerModel
    let onboardingRepository: any OnboardingRepository
    let settingsRepository: any SettingsRepository
    let storeKitService: StoreKitService
    let entitlementService: EntitlementService
    let apnsManager: APNSRegistrationManager
    let notificationSettingsModel: NotificationSettingsModel
    let notificationInboxModel: NotificationInboxModel
    let syncEngine: SyncEngine
    let downloadManager: DownloadManager
    let analytics: DefaultAnalyticsClient

    let permit: SessionWorkPermit
    private let teardownPermit: SessionWorkPermit
    private let backgroundBroker: SessionBackgroundWorkBroker
    private var wasAudioPlaying = false

    static func storeKitAccountBinding(
        for context: AccountContext
    ) -> StoreKitAccountBinding? {
        StoreKitAccountBinding(accountID: context.accountID)
    }

    // This is the composition root for the complete private graph; keeping the
    // construction in one initializer makes partial account graphs impossible.
    // swiftlint:disable:next function_body_length
    init(
        context: AccountContext,
        permit: SessionWorkPermit,
        apiClientFactory: LiveAPIClientFactory,
        session: SessionManager,
        persistence: AccountPersistenceResources,
        config: AppConfig,
        reachability: ReachabilityService,
        backgroundBroker: SessionBackgroundWorkBroker
    ) throws {
        precondition(persistence.matches(storageNamespace: context.storageNamespace))
        self.context = context
        self.permit = permit
        self.persistence = persistence
        self.backgroundBroker = backgroundBroker
        let teardownPermit = SessionWorkPermit(initialState: .quiesced)
        self.teardownPermit = teardownPermit

        let accountTokenProvider = AccountBoundSessionTokenProvider(
            context: context,
            session: session,
            permit: permit
        )
        let baseAPIClient = apiClientFactory.make(tokenProvider: accountTokenProvider)
        let client = SessionScopedAPIClient(
            base: baseAPIClient,
            context: context,
            session: session,
            permit: permit
        )
        apiClient = client
        let container = persistence.controller.container
        let syncEngine = SyncEngine(apiClient: client, container: container)
        self.syncEngine = syncEngine
        let presentationStores = SessionPresentationStores.account(context: context)
        let keyValueStore = presentationStores.keyValueStore
        let preferences = presentationStores.preferences
        self.keyValueStore = keyValueStore
        self.preferences = preferences
        dailyGoalStore = presentationStores.dailyGoalStore

        libraryRepository = LiveLibraryRepository(
            client: client,
            container: container,
            reachability: reachability
        )
        bookDetailRepository = LiveBookDetailRepository(client: client)
        socialRepository = try LiveSocialRepository(
            client: client,
            storageNamespace: context.storageNamespace,
            workPermit: permit
        )
        aiRepository = LiveAIRepository(client: client, accountID: context.accountID)
        readerRepository = LiveReaderRepository(
            client: client,
            store: keyValueStore,
            container: container,
            reachability: reachability,
            accountID: context.accountID,
            workPermit: permit
        )
        quizRepository = LiveQuizRepository(
            client: client,
            container: container,
            reachability: reachability,
            accountID: context.accountID,
            workPermit: permit
        )
        annotationRepository = LiveAnnotationRepository(
            container: container,
            accountID: context.accountID,
            triggerSync: { [syncEngine, accountID = context.accountID] in
                await syncEngine.triggerDrain(userId: accountID)
            },
            workPermit: permit
        )
        reviewsRepository = ReviewsRepository(
            apiClient: client,
            modelContainer: container,
            workPermit: permit
        )
        onboardingRepository = LiveOnboardingRepository(apiClient: client)
        settingsRepository = LiveSettingsRepository(client: client)

        let audioPlayer = AudioPlayer(repository: LiveAudioRepository(client: client))
        audioPlayerModel = AudioPlayerModel(player: audioPlayer, preferences: preferences)

        let storeKitService = StoreKitService(
            apiClient: client,
            config: StoreKitConfig.from(config),
            accountBinding: Self.storeKitAccountBinding(for: context)
        )
        self.storeKitService = storeKitService
        entitlementService = EntitlementService(
            storeKitService: storeKitService,
            apiClient: client,
            storeKitConfig: StoreKitConfig.from(config),
            store: keyValueStore
        )

        #if os(iOS)
        let authorizer: any NotificationAuthorizerProtocol = NotificationAuthorizer()
        #else
        let authorizer: any NotificationAuthorizerProtocol = SessionHostNotificationAuthorizer()
        #endif
        let teardownTokenProvider = AccountBoundSessionTokenProvider(
            context: context,
            session: session,
            permit: teardownPermit
        )
        let teardownBaseAPIClient = apiClientFactory.make(
            tokenProvider: teardownTokenProvider
        )
        let teardownClient = SessionScopedAPIClient(
            base: teardownBaseAPIClient,
            context: context,
            session: session,
            permit: teardownPermit
        )
        let registrationRepository = LiveDeviceRegistrationRepository(apiClient: teardownClient)
        apnsManager = APNSRegistrationManager(
            authorizer: authorizer,
            repository: registrationRepository,
            storageNamespace: context.storageNamespace
        )
        notificationSettingsModel = NotificationSettingsModel(
            repository: LiveNotificationPreferencesRepository(apiClient: client),
            authorizer: authorizer,
            pendingStore: keyValueStore
        )
        notificationInboxModel = NotificationInboxModel(
            repository: LiveNotificationInboxRepository(
                apiClient: client,
                storageNamespace: context.storageNamespace,
                workPermit: permit
            )
        )
        downloadManager = DownloadManager(
            resources: persistence,
            apiClient: client,
            preferences: preferences,
            workPermit: permit
        )

        let analyticsBaseURL = URL(string: config.apiBaseURL)
            ?? URL(string: "https://invalid.chapterflow.invalid")!
        let analyticsTokenProvider = AccountBoundSessionTokenProvider(
            context: context,
            session: session,
            permit: permit
        )
        let analyticsTransport = URLSessionAnalyticsTransport(
            baseURL: analyticsBaseURL,
            tokenProvider: { [analyticsTokenProvider] in
                try? await analyticsTokenProvider.validToken()
            }
        )
        analytics = try DefaultAnalyticsClient.makeDurable(
            transport: analyticsTransport,
            storageNamespace: context.storageNamespace,
            workPermit: permit
        )
    }

    func activate() async {
        // APNs uses the teardown-bound client for both normal registration and
        // sign-out unregistration. Keep that permit active for the lifetime of
        // the scope, then quiesce it only after sign-out work completes.
        await teardownPermit.resume()
        entitlementService.start()
        apnsManager.start()
        await syncEngine.start(userId: context.accountID)
        await backgroundBroker.install(backgroundWork)
        await analytics.flush()
    }

    func quiesce() async {
        await teardownPermit.resume()
        await entitlementService.pause()
        await downloadManager.pause()
        wasAudioPlaying = await audioPlayerModel.pauseForSessionBoundary()
        _ = await apnsManager.handleSignOut()
        await notificationSettingsModel.cancelAndReset()
        notificationInboxModel.cancelAndReset()
        await reviewsRepository.invalidate()
        await analytics.suspendForSessionBoundary()
        await syncEngine.stop()
        await backgroundBroker.remove(scopeID: context.instanceID)
        await teardownPermit.quiesce()
    }

    func resume() async {
        await teardownPermit.resume()
        await entitlementService.resume()
        await downloadManager.resume()
        await analytics.resumeAfterSessionBoundary()
        apnsManager.resume()
        await syncEngine.start(userId: context.accountID)
        await backgroundBroker.install(backgroundWork)
        await audioPlayerModel.resumeAfterSessionBoundary(
            shouldResumePlayback: wasAudioPlaying
        )
        wasAudioPlaying = false
    }

    func invalidate() async {
        await teardownPermit.invalidate()
        await backgroundBroker.remove(scopeID: context.instanceID)
        await entitlementService.stop()
        await downloadManager.invalidate()
        apnsManager.stopAndReset()
        await notificationSettingsModel.cancelAndReset()
        notificationInboxModel.cancelAndReset()
        await syncEngine.stop()
        await audioPlayerModel.stopForSessionBoundary()
        #if os(iOS)
        // Review scheduling is disabled until it has account-scoped ownership.
        // Remove any legacy pending or delivered A presentation only at
        // irreversible teardown so a failed sign-out can resume the exact A
        // scope without losing state during the reversible phase.
        await ReviewNotificationScheduler.shared.cancelAll()
        #endif
        await analytics.suspendForSessionBoundary()
    }

    private var backgroundWork: SessionBackgroundWork {
        let accountID = context.accountID
        let scopeID = context.instanceID
        let syncEngine = syncEngine
        let entitlementService = entitlementService
        let downloadManager = downloadManager
        return SessionBackgroundWork(
            scopeID: scopeID,
            refresh: {
                await syncEngine.drainAndWait(userId: accountID)
                guard !Task.isCancelled else { return }
                await entitlementService.refresh()
            },
            processing: {
                await downloadManager.resumeInterruptedDownloads(userId: accountID)
                guard !Task.isCancelled else { return }
                await downloadManager.prefetchNextChapters(userId: accountID)
            }
        )
    }
}

struct DefaultSessionScopeFactory {
    let config: ValidatedAppConfig
    let apiClientFactory: LiveAPIClientFactory
    let session: SessionManager
    let persistenceLoader: any AccountPersistenceLoading
    let reachability: ReachabilityService
    let backgroundBroker: SessionBackgroundWorkBroker

    @MainActor
    func make(context: AccountContext) async throws -> SessionScope {
        try Task.checkCancellation()
        let persistence = try await persistenceLoader.load(
            storageNamespace: context.storageNamespace
        )
        try Task.checkCancellation()
        guard persistence.matches(storageNamespace: context.storageNamespace) else {
            throw AccountPersistenceLoadFailure.invalidStorageNamespace
        }
        let permit = SessionWorkPermit()
        let graph = try SessionPrivateGraph(
            context: context,
            permit: permit,
            apiClientFactory: apiClientFactory,
            session: session,
            persistence: persistence,
            config: config.value,
            reachability: reachability,
            backgroundBroker: backgroundBroker
        )
        return SessionScope(
            context: context,
            permit: permit,
            graph: graph,
            operations: SessionScopeOperations(
                activate: { [graph] in await graph.activate() },
                quiesce: { [graph] in await graph.quiesce() },
                resume: { [graph] in await graph.resume() },
                invalidate: { [graph] in await graph.invalidate() }
            )
        )
    }
}

#if !os(iOS)
private struct SessionHostNotificationAuthorizer: NotificationAuthorizerProtocol {
    func currentStatus() async -> NotificationPermissionStatus { .denied }
    func requestAuthorization() async -> NotificationAuthorizationOutcome { .denied }
    func requestProvisionalAuthorization() async -> NotificationAuthorizationOutcome { .denied }
}
#endif
