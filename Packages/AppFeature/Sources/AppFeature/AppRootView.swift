import SwiftUI
import CoreKit
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

/// The top-level entry point for the app's UI.
///
/// Gates content on `AuthState`:
/// - `.unknown`        → `ProgressView` (Amplify resolving startup state)
/// - `.signedOut`      → `AuthFlowView` (Welcome / sign-in + email flows)
/// - `.signedIn`       → main `TabView` (sidebarAdaptable, Liquid Glass tab bar)
/// - `.reconnecting`   → main `TabView` + non-destructive top banner
/// - `.reauthRequired` → main `TabView` + `ReauthView` sheet (blocking)
public struct AppRootView: View {
    @State private var model: AppModel
    @State private var readingFlow: ReadingFlow?

    public init(config: AppConfig = .fromInfoPlist()) {
        _model = State(initialValue: AppModel(config: config))
    }

    public var body: some View {
        gatedContent
            .task {
                try? model.configure()
                model.wirePushRouting()
            }
            .onOpenURL { url in model.handle(url: url) }
            .onChange(of: model.session.authState) { _, newState in
                switch newState {
                case .signedIn:
                    model.hydrateDisplayName()
                    model.startAPNS()
                    model.showAuthGate = false
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
                        repository: model.onboardingRepository
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
                onDismiss: { readingFlow = nil }
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
        case .library:
            LibraryView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: model.aiRepository,
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
            ReviewsView(model: ReviewsModel(repository: model.reviewsRepository))
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
                    onSignOut: { await model.signOut() }
                ),
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

    // MARK: - Guest tab content

    @ViewBuilder
    private func guestTabContent(for tab: AppTab) -> some View {
        let authGateClosure: (String, VariantFamily) -> Void = { bookId, variantFamily in
            model.requestAuth(intent: .startBook(bookId: bookId, variantFamily: variantFamily))
        }
        let requireAuthClosure: () -> Void = {
            model.requestAuth(intent: .none)
        }

        switch tab {
        case .home:
            HomeView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: model.aiRepository,
                isGuest: true,
                onOpenReader: nil, // guests can't open the reader
                onShowPaywall: nil,
                onRequireAuth: requireAuthClosure,
                onSignInRequired: authGateClosure
            )
        case .library:
            LibraryView(
                repository: model.libraryRepository,
                bookDetailRepository: model.bookDetailRepository,
                aiRepository: model.aiRepository,
                isGuest: true,
                onOpenReader: nil,
                onShowPaywall: nil,
                onRequireAuth: requireAuthClosure,
                onSignInRequired: authGateClosure
            )
        case .reviews:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "star",
                    title: "Reviews",
                    description: "Create a free account to access spaced-repetition reviews.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Reviews")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        case .profile:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "person.crop.circle",
                    title: "Profile",
                    description: "Create a free account to track your progress and connect with others.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Profile")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        case .settings:
            NavigationStack {
                GuestTabEmptyView(
                    systemImage: "gearshape",
                    title: "Settings",
                    description: "Create a free account to access settings.",
                    onCreateAccount: requireAuthClosure
                )
                .navigationTitle("Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
            }
        }
    }
}

// MARK: - Reconnecting banner

/// A floating glass pill shown when the app is attempting to reconnect.
private struct ReconnectingBanner: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: .cfSpacing8) {
            ProgressView().scaleEffect(0.8)
            Text("Reconnecting…").font(.cfFootnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
        .background(bannerBackground, in: Capsule())
        .padding(.top, .cfSpacing8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Reconnecting to the server")
    }

    private var bannerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Previews

#Preview("Tab Shell — signed in") {
    AppRootView()
}

#Preview("Reconnecting banner") {
    ReconnectingBanner()
}

#if DEBUG
#Preview("Guest Home — browsing") {
    let view = AppRootView()
    return view
}
#endif
