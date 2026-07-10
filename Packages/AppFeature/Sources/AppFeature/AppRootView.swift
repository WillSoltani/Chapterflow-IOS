import SwiftUI
import StoreKit
import CoreKit
import CoreSpotlight
import DesignSystem
import Models
import Networking
import Persistence
import AuthKit
import LibraryFeature
import ReaderFeature
import QuizFeature
import PaywallFeature
import EngagementFeature
import AIFeature
import SocialFeature
import NotificationsFeature
import OnboardingFeature
import SettingsFeature
import SyncEngine

/// The top-level entry point for the app's UI.
///
/// Gates content on `AuthState`:
/// - `.unknown`        → `ProgressView` (Amplify resolving startup state)
/// - `.signedOut`      → `AuthFlowView` (Welcome / sign-in + email flows)
/// - `.signedIn`       → main `TabView` (sidebarAdaptable, Liquid Glass tab bar)
/// - `.reconnecting`   → main `TabView` + non-destructive top banner
/// - `.reauthRequired` → main `TabView` + `ReauthView` sheet (blocking)
public struct AppRootView: View {
    // `private(set)`, not `private`, so same-module extensions split across files
    // (e.g. AppRootView+TabContent, +Banners, +WhatsNew) can read it. Setter stays private.
    @State private(set) var model: AppModel
    @State private var readingFlow: ReadingFlow?
    @State private var showQueuedToast = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    // Observed so SwiftUI tracks changes written by App Intents perform().
    private let intentStore = IntentActionStore.shared

    public init(config: AppConfig = .fromInfoPlist()) {
        _model = State(initialValue: AppModel(config: config))
    }

    public var body: some View {
        gatedContent
            // Force-update / maintenance gate (B4) — one hook covering every screen.
            .appConfigGate(model.appConfigService)
            #if DEBUG
            .shakeToDebug(model: model)
            #endif
            .environment(model.reachability)
            .task {
                try? model.configure()
                model.wirePushRouting()
                Task { await model.appConfigService.refresh() } // fails open on error
                model.analytics.track(.appOpen)
                // Defer non-critical work so the first interactive frame lands quickly.
                // analytics.flush() is a network call — fire and forget, don't await.
                // IntentDonationManager reads the App Intents catalog — background-safe.
                Task(priority: .utility) {
                    IntentDonationManager.update()
                }
                Task { await model.analytics.flush() }
            }
            .onOpenURL { url in model.handle(url: url) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.consumeAudioControlCommand()
                    model.consumePendingReadingMinutes()
                    model.consumeControlIntentAction()
                    model.triggerForegroundSync()
                    model.drainExtensionOutbox()
                    Task { await model.appConfigService.refresh() } // re-check gate on foreground
                case .background:
                    model.scheduleBackgroundTasks()
                    model.analytics.beacon("app_background")
                    Task { await model.analytics.flush() }
                default:
                    break
                }
            }
            .onChange(of: model.audioPlayerModel.isPlaying) { _, isPlaying in
                model.publishAudioPlayingState(isPlaying)
            }
            .onChange(of: intentStore.pendingDeepLink) { _, link in
                guard let link else { return }
                intentStore.pendingDeepLink = nil
                model.handle(deepLink: link)
            }
            .onChange(of: intentStore.pendingAudioPlay) { _, request in
                guard let request else { return }
                intentStore.pendingAudioPlay = nil
                Task {
                    await model.audioPlayerModel.play(
                        bookId: request.bookId,
                        chapterNumber: request.chapterNumber
                    )
                }
            }
            .onChange(of: model.session.authState) { _, newState in
                switch newState {
                case .signedIn:
                    model.hydrateDisplayName()
                    model.startAPNS()
                    model.startSyncEngine()
                    model.showAuthGate = false
                    model.startSpotlightIndexing()
                    // Replay any action the guest was attempting before signing in.
                    if !model.pendingAuthIntent.isNone {
                        Task { await model.replayPendingIntent { readingFlow = $0 } }
                    } else {
                        model.isGuestMode = false
                    }
                case .signedOut:
                    model.displayName = ""
                default:
                    break
                }
            }
            // Core Spotlight — activity from a Spotlight search result.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard
                    let urlString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                    let url = URL(string: urlString)
                else { return }
                model.handle(url: url)
            }
            // Universal Links — iOS delivers https://chapterflow.ca/... and
            // https://app.chapterflow.ca/... taps as NSUserActivityTypeBrowsingWeb
            // with the URL in `webpageURL`. onOpenURL only covers custom-scheme
            // URLs, so this handler is needed for Universal Links from Safari, etc.
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                model.handle(url: url)
            }
            // Continuity Handoff — resume a reading session advertised by another
            // iOS device (or this device's prior session) via userActivity(_:).
            .onContinueUserActivity(HandoffActivityType.reading) { activity in
                guard
                    let info = activity.userInfo,
                    let bookId = info[HandoffKeys.bookId] as? String,
                    let chapter = info[HandoffKeys.chapterNumber] as? Int
                else { return }
                let variantRaw = info[HandoffKeys.variantFamily] as? String
                model.handleHandoff(bookId: bookId, chapterNumber: chapter, variantFamilyRaw: variantRaw)
            }
            // Open the reader directly when a Handoff or intent sets pendingHandoffFlow.
            .onChange(of: model.pendingHandoffFlow) { _, flow in
                guard let flow else { return }
                model.pendingHandoffFlow = nil
                readingFlow = flow
            }
            .onChange(of: model.syncStatus?.pendingCount) { oldCount, newCount in
                guard !model.reachability.isConnected else { return }
                guard let old = oldCount, let new = newCount, new > old else { return }
                showQueuedToast = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showQueuedToast = false
                }
            }
    }

    // MARK: - Auth-gated root content

    @ViewBuilder
    private var gatedContent: some View {
        // DEBUG: pass `--demo-tab-shell` as a launch argument to skip auth
        // and land directly on the tab shell (e.g. for simulator walkthroughs).
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-tab-shell") {
            mainTabView
        } else {
            authGatedContent
        }
        #else
        authGatedContent
        #endif
    }

    @ViewBuilder
    private var authGatedContent: some View {
        switch model.session.authState {
        case .unknown:
            ProgressView()
                .accessibilityLabel("Loading")

        case .signedOut:
            // Guest mode: show the full tab shell with public content available.
            // The auth gate sheet and affordance pill are layered on top.
            if model.isGuestMode {
                guestTabView
            } else {
                authFlowContent
            }

        case .signedIn, .reauthRequired, .reconnecting:
            mainTabView
                .sheet(isPresented: .constant(model.session.authState == .reauthRequired)) {
                    ReauthView(sessionManager: model.session)
                        .interactiveDismissDisabled(true)
                }
                .overlay(alignment: .top) {
                    if model.session.authState == .reconnecting {
                        ReconnectingBanner()
                            .animation(.spring, value: model.session.authState)
                    }
                }
                // First-run onboarding — dismissed automatically when preferences.onboardingCompleted
                // becomes true (set by OnboardingModel after completing or skipping the flow).
                #if os(iOS)
                .fullScreenCover(
                    isPresented: Binding(
                        get: { !model.preferences.onboardingCompleted },
                        set: { _ in }
                    )
                ) {
                    OnboardingFlowView(
                        preferences: model.preferences,
                        repository: model.onboardingRepository,
                        analytics: model.analytics
                    )
                }
                #endif
        }
    }

    @ViewBuilder
    private var authFlowContent: some View {
        #if os(iOS)
        AuthFlowView(
            authService: model.authService,
            onBrowseAsGuest: { model.enterGuestMode() }
        )
        #else
        EmptyView()
        #endif
    }

    // MARK: - Guest tab view

    /// Tab shell for unauthenticated guests — same layout as `mainTabView` but
    /// with the auth gate sheet and affordance pill layered on top.
    private var guestTabView: some View {
        guestTabShell
            #if os(iOS)
            .sheet(isPresented: Binding(
                get: { model.showAuthGate },
                set: { model.showAuthGate = $0 }
            )) {
                AuthGateSheet(
                    authService: model.authService,
                    intent: model.pendingAuthIntent
                )
                .presentationDetents([.large])
            }
            #endif
    }

    private var guestTabShell: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                guestTabContent(for: .home)
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                guestTabContent(for: .library)
            }
            Tab("Reviews", systemImage: "star", value: AppTab.reviews) {
                guestTabContent(for: .reviews)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                guestTabContent(for: .profile)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                guestTabContent(for: .settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.cfAccent)
        .safeAreaInset(edge: .bottom) {
            GuestAffordancePill {
                model.requestAuth(intent: .none)
            }
        }
        .overlay(alignment: .top) {
            OfflineBannerView(isOffline: !model.reachability.isConnected)
                .padding(.top, .cfSpacing8)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.reachability.isConnected)
        }
    }

    // MARK: - Main tab view

    /// Five-tab shell using the iOS 18 `Tab { }` API with `.sidebarAdaptable`
    /// so iPad gets a collapsible sidebar and iPhone/Mac get a native tab bar
    /// (which receives the Liquid Glass treatment automatically on iOS/macOS 26+).
    private var mainTabView: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                tabContent(for: .home)
            }
            .badge(model.notificationInboxModel.unreadCount)
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                tabContent(for: .library)
            }
            Tab("Reviews", systemImage: "star", value: AppTab.reviews) {
                tabContent(for: .reviews)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                tabContent(for: .profile)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                tabContent(for: .settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.cfAccent)
        .environment(model.audioPlayerModel)
        .safeAreaInset(edge: .bottom) {
            MiniPlayerBar()
                .environment(model.audioPlayerModel)
        }
        #if os(iOS)
        .fullScreenCover(item: $readingFlow) { flow in
            ReadingFlowView(
                flow: flow,
                readerRepository: model.readerRepository,
                quizRepository: model.quizRepository,
                annotationRepository: model.annotationRepository,
                preferences: model.preferences,
                analytics: model.analytics,
                onDismiss: { readingFlow = nil },
                onQuizPassed: { requestReviewAfterQuizPass(model, requestReview) }
            )
        }
        #endif
        .sheet(isPresented: Binding(
            get: { model.showPaywall },
            set: { model.showPaywall = $0 }
        )) {
            PaywallView(model: model.makePaywallModel(context: model.paywallContext))
        }
        // Gift-claim sheet — presented when a chapterflow://gift/{code} deep link
        // lands or the user taps "Redeem Gift Code" from the Profile tab.
        .sheet(isPresented: Binding(
            get: { model.pendingGiftCode != nil },
            set: { if !$0 { model.pendingGiftCode = nil } }
        )) {
            if let code = model.pendingGiftCode {
                GiftClaimView(
                    code: code,
                    repository: model.socialRepository,
                    onClaimed: { model.pendingGiftCode = nil }
                )
            }
        }
        // Subscription management sheet — full billing lifecycle detail and CTAs.
        .sheet(isPresented: Binding(
            get: { model.showSubscriptionManagement },
            set: { model.showSubscriptionManagement = $0 }
        )) {
            SubscriptionManagementView(
                model: model.makeSubscriptionManagementModel(),
                onShowPaywall: {
                    model.showSubscriptionManagement = false
                    model.paywallContext = .settings
                    model.showPaywall = true
                }
            )
        }
        // Global offline banner — floats at the top; clears automatically on reconnect.
        .overlay(alignment: .top) {
            OfflineBannerView(
                isOffline: !model.reachability.isConnected,
                pendingCount: model.syncStatus?.pendingCount ?? 0
            )
            .padding(.top, .cfSpacing8)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.reachability.isConnected)
        }
        // Queued-action confirmation toast shown when an offline write is enqueued.
        .offlineQueuedToast(isPresented: $showQueuedToast)
        // Extension inbox banner: shown when the Share/Action extension saved items.
        .overlay(alignment: .top) {
            if model.showExtensionInboxBanner {
                ExtensionInboxBanner(count: model.extensionInboxCount)
                    .padding(.top, .cfSpacing8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.spring) { model.showExtensionInboxBanner = false }
                    }
            }
        }
        .animation(.spring, value: model.showExtensionInboxBanner)
        // Notification inbox — presented by the bell button in the Home toolbar
        // or by a chapterflow://notifications deep link.
        .sheet(isPresented: Binding(
            get: { model.showNotificationInbox },
            set: { model.showNotificationInbox = $0 }
        )) {
            NotificationInboxView(
                model: model.notificationInboxModel,
                onOpenURL: { url in
                    model.showNotificationInbox = false
                    model.handle(url: url)
                }
            )
        }
        // What's New (P10.9) — auto-presents once after an app update (self-contained).
        .whatsNewLaunchGate(onboardingCompleted: model.preferences.onboardingCompleted)
    }

    // MARK: - Tab content

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: model.aiRepository,
                analytics: model.analytics,
                onOpenReader: { bookId, chapterNumber, variantFamily in
                    readingFlow = ReadingFlow(
                        bookId: bookId,
                        chapterNumber: chapterNumber,
                        variantFamily: variantFamily
                    )
                },
                onShowPaywall: {
                    model.paywallContext = .lockedFeature(featureName: "Book")
                    model.showPaywall = true
                },
                onShowNotificationInbox: {
                    model.showNotificationInbox = true
                }
            )
        case .library:
            LibraryView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: model.aiRepository,
                analytics: model.analytics,
                onOpenReader: { bookId, chapterNumber, variantFamily in
                    readingFlow = ReadingFlow(
                        bookId: bookId,
                        chapterNumber: chapterNumber,
                        variantFamily: variantFamily
                    )
                },
                onShowPaywall: {
                    model.paywallContext = .lockedFeature(featureName: "Book")
                    model.showPaywall = true
                }
            )
        case .profile:
            ProfileView(
                repository: model.socialRepository,
                pendingPairAcceptCode: $model.pendingPairAcceptCode,
                pendingReferralCode: $model.pendingReferralCode
            )
        case .reviews:
            ReviewsView(model: ReviewsModel(repository: model.reviewsRepository, analytics: model.analytics))
        case .settings:
            SettingsView(
                isPro: model.entitlementService.isPro,
                remainingFreeStarts: model.entitlementService.remainingFreeStarts,
                currentPeriodEnd: model.entitlementService.currentPeriodEnd,
                cancelAtPeriodEnd: model.entitlementService.cancelAtPeriodEnd,
                onShowPaywall: {
                    model.paywallContext = .settings
                    model.showPaywall = true
                },
                onManageSubscription: {
                    model.showSubscriptionManagement = true
                },
                pushStatus: model.apnsManager.pushStatus,
                pushRegistrationError: model.apnsManager.registrationError,
                onManagePushSettings: {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Task { await UIApplication.shared.open(url) }
                    }
                    #endif
                },
                notificationSettingsModel: model.notificationSettingsModel,
                settingsModel: SettingsModel(
                    repository: model.settingsRepository,
                    preferences: model.preferences,
                    onSignOut: { await model.signOut() },
                    downloadInfoProvider: model.downloadInfoProvider,
                    userId: {
                        if case .signedIn(let user) = model.session.authState {
                            return user.userId
                        }
                        return ""
                    }()
                ),
                syncStatus: model.syncStatus,
                userEmail: model.displayName.isEmpty ? nil : {
                    if let token = model.session.currentIdToken(),
                       let profile = UserProfile.from(idToken: token) {
                        return profile.email
                    }
                    return nil
                }(),
                onSignOut: { await model.signOut() }
            )
        }
    }
}

// `ReconnectingBanner` is defined in AppRootView+Banners.swift (P8.6).

// MARK: - Previews

#Preview("Tab Shell — signed in") {
    AppRootView()
}

#Preview("Reconnecting banner") {
    ReconnectingBanner()
}
