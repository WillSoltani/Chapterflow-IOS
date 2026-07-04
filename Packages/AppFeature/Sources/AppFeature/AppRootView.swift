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
            authFlowContent

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
        AuthFlowView(authService: model.authService)
        #else
        EmptyView()
        #endif
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
                    model.openManageSubscriptions()
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
