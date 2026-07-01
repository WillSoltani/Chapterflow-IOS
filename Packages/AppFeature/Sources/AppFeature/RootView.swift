import SwiftUI
import CoreKit

/// The top-level view: shows a splash while the session resolves, then either
/// the (stubbed) auth flow or the main tab shell. Owns the shared `TabRouter`
/// and `ToastPresenter`, applies the theme, installs the toast layer, and routes
/// incoming deep links / Handoff activities.
struct RootView: View {
    @Environment(\.dependencies) private var dependencies

    @State private var model: AppRootModel?
    @State private var tabRouter = TabRouter()
    @State private var toastPresenter = ToastPresenter()
    /// A deep link that arrived before the shell was ready; applied on `.ready`.
    @State private var pendingTarget: DeepLinkTarget?

    var body: some View {
        content
            .environment(tabRouter)
            .environment(toastPresenter)
            .preferredColorScheme(dependencies.preferences.themeMode.colorScheme)
            .toastLayer(toastPresenter)
            .task {
                // Build the model against the injected container and launch once.
                guard model == nil else { return }
                // Seed a launch-time deep link (UITest affordance) up front so it
                // is applied the moment the shell becomes ready, rather than after
                // the best-effort remote-config fetch inside start().
                seedLaunchDeepLinkIfNeeded()
                let model = AppRootModel(dependencies: dependencies)
                self.model = model
                await model.start()
            }
            .onChange(of: model?.phase) { _, phase in
                // Flush a deferred deep link once the shell exists.
                if phase == .ready, let target = pendingTarget {
                    tabRouter.apply(target)
                    pendingTarget = nil
                }
            }
            .onOpenURL { url in handle(url: url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { handle(url: url) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model?.phase ?? .launching {
        case .launching:
            SplashView()
                .transition(.opacity)
        case .signedOut:
            AuthFlowView { didSignIn() }
                .transition(.opacity)
        case .ready:
            MainTabView()
                .transition(.opacity)
        }
    }

    /// Resolves a URL to a target and applies it now (if the shell is up) or
    /// defers it until launch completes.
    private func handle(url: URL) {
        guard let target = DeepLinkParser.target(for: url) else { return }
        if model?.phase == .ready {
            tabRouter.apply(target)
        } else {
            pendingTarget = target
        }
    }

    /// UITest / debug affordance: stage a deep link passed at launch via the
    /// `CF_DEEPLINK` environment variable as the pending target, so it routes
    /// through the normal ``TabRouter`` path as soon as the shell is ready. This
    /// exists so automated tests (and manual `simctl launch`) can exercise
    /// routing without the SpringBoard "Open in app?" confirmation that
    /// `simctl openurl` triggers. It is inert unless the variable is set, so it
    /// never affects a normal launch.
    private func seedLaunchDeepLinkIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["CF_DEEPLINK"],
              let url = URL(string: raw),
              let target = DeepLinkParser.target(for: url) else { return }
        pendingTarget = target
    }

    /// Stubbed sign-in: seed the token store, then flip the model to `.ready`.
    private func didSignIn() {
        Task {
            if let store = dependencies.tokenStore as? StubTokenStore {
                await store.set("stub-id-token")
            }
            dependencies.analytics.track(.signIn(method: "stub"))
            model?.didSignIn()
        }
    }
}

// MARK: - Splash

/// The launch splash shown while the session resolves. A calm wordmark, no
/// spinner — deferential to content, per the Apple "Pro" bar.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("ChapterFlow")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ChapterFlow")
    }
}

#Preview("Splash") {
    SplashView()
}
