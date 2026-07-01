import Foundation
import Observation
import CoreKit
import Networking

/// Owns the app's launch lifecycle and top-level auth phase.
///
/// On ``start()`` it: emits `app_open`, resolves the session (is there a usable
/// token?), and — best-effort, non-blocking — fetches remote config to seed
/// feature flags. The ``phase`` it publishes drives ``RootView``'s splash →
/// auth/shell transition.
@MainActor
@Observable
public final class AppRootModel {
    /// The coarse launch/auth state the root renders from.
    public enum Phase: Equatable, Sendable {
        /// Resolving the session; the splash is shown.
        case launching
        /// No usable session; show the (stubbed) auth flow.
        case signedOut
        /// Session resolved; show the tab shell.
        case ready
    }

    public private(set) var phase: Phase = .launching

    private let dependencies: Dependencies
    private let log = AppLog(category: .app)

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Runs the launch sequence. Safe to call once from a root `.task`.
    public func start() async {
        dependencies.analytics.track(.appOpen)
        await resolveSession()
        // Config is best-effort and must not gate the shell: the session has
        // already resolved above, so the splash is gone before this runs.
        await fetchConfig()
    }

    /// Sets ``phase`` based on whether a token is available. Any error while
    /// reading the token is treated as signed-out.
    func resolveSession() async {
        do {
            let token = try await dependencies.tokenStore.validToken()
            let hasSession = (token?.isEmpty == false)
            phase = hasSession ? .ready : .signedOut
        } catch {
            log.error("session resolve failed: \(error.localizedDescription)")
            phase = .signedOut
        }
    }

    /// Fetches `GET /book/config/ios` and applies it to the feature flags.
    /// Failures are swallowed — flags fall back to safe local defaults.
    func fetchConfig() async {
        do {
            let endpoint = Endpoint(method: .get, path: "/book/config/ios", requiresAuth: false)
            let config: IOSConfig = try await dependencies.api.send(endpoint)
            dependencies.featureFlags.apply(config)
        } catch {
            log.debug("remote config unavailable; using local flag defaults")
        }
    }

    /// Called by the stubbed auth flow once a token has been stored.
    public func didSignIn() {
        phase = .ready
    }

    /// Resets to signed-out and clears remote flag overrides.
    public func signOut() {
        dependencies.featureFlags.reset()
        dependencies.analytics.track(.signOut)
        phase = .signedOut
    }
}
