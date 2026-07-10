import Foundation
import SwiftUI
import CoreKit
import Networking
import Persistence

/// Fetches `GET /book/config/ios` (B4) at launch and on foreground and derives
/// the force-update / maintenance ``AppConfigGateState`` that `AppRootView`
/// renders.
///
/// **Fail-open is the load-bearing invariant.** Any fetch or parse failure never
/// locks the user out: the service falls back to the last-good cached config (so
/// a legitimate gate survives offline) or, when there is no cache, to `.none`.
/// The last-good config is persisted to App Group `UserDefaults` for offline use.
@Observable
@MainActor
public final class AppConfigService {

    /// The current gate state, recomputed on every `refresh()`. Drives the UI.
    public private(set) var gateState: AppConfigGateState = .none

    /// The last successfully-applied config (fetched or loaded from cache), kept
    /// so the UI can read `appStoreURL` / feature flags. `nil` before the first
    /// successful load with no cache present.
    public private(set) var config: IOSAppConfig?

    /// The App Store URL for the update button: the server-provided link when
    /// present, otherwise a built-in fallback that reliably opens the App Store.
    public var appStoreURL: URL {
        if let raw = config?.appStoreURL, let url = URL(string: raw) {
            return url
        }
        return Self.fallbackAppStoreURL
    }

    /// Whether the soft "update available" nudge should currently be shown: true
    /// only when the state is `.softNudge` and the user hasn't already dismissed
    /// the nudge for that specific version.
    public var shouldShowSoftNudge: Bool {
        guard case .softNudge(let latest, _) = gateState else { return false }
        return dismissedNudgeVersion == nil || dismissedNudgeVersion != latest
    }

    // MARK: - Dependencies

    private let apiClient: any APIClientProtocol
    private let currentVersion: String
    private let store: KeyValueStore

    private static let cacheKey = "appConfig.lastGood"
    private static let dismissedNudgeKey = "appConfig.dismissedNudgeVersion"

    /// The App Store version for which the user tapped "Later" on the soft nudge,
    /// so it doesn't re-nag on every foreground. Persisted across launches.
    private var dismissedNudgeVersion: String?

    /// Fallback App Store link used when the server config omits `appStoreURL`.
    /// Production should supply the exact product URL via the B4 config; this
    /// search link reliably opens the App Store without a fabricated product id.
    static let fallbackAppStoreURL = URL(
        string: "itms-apps://itunes.apple.com/search?media=software&term=ChapterFlow"
    ) ?? URL(string: "https://apps.apple.com")!

    // MARK: - Init

    public init(
        apiClient: any APIClientProtocol,
        currentVersion: String? = nil,
        store: KeyValueStore = KeyValueStore()
    ) {
        self.apiClient = apiClient
        // `Bundle.appShortVersion` is module-internal, so it can't be a default
        // argument on this public init — resolve it here instead.
        let version = currentVersion ?? Bundle.main.appShortVersion
        self.currentVersion = version
        self.store = store
        self.dismissedNudgeVersion = store.value(String.self, forKey: Self.dismissedNudgeKey)
        // Seed synchronously from any cached config so a blocking gate is honoured
        // instantly at launch, before the network round-trip completes.
        if let cached = store.value(IOSAppConfig.self, forKey: Self.cacheKey) {
            self.config = cached
            self.gateState = AppConfigGate.evaluate(config: cached, currentVersion: version)
        }
    }

    // MARK: - Refresh

    /// Fetches the latest config and recomputes the gate. Call at launch and on
    /// every foreground activation. Never throws — failures fail open.
    public func refresh() async {
        #if DEBUG
        if let forced = Self.debugForcedState() {
            gateState = forced
            return
        }
        #endif
        do {
            let fresh: IOSAppConfig = try await apiClient.send(Endpoints.getIOSConfig())
            cache(fresh)
            config = fresh
            gateState = AppConfigGate.evaluate(config: fresh, currentVersion: currentVersion)
        } catch {
            // FAIL OPEN: fall back to last-good cached config (or none). A fetch
            // failure must never introduce a lock the server didn't ask for.
            let cached = store.value(IOSAppConfig.self, forKey: Self.cacheKey)
            config = cached
            gateState = AppConfigGate.evaluate(config: cached, currentVersion: currentVersion)
        }
    }

    /// Records that the user dismissed the soft nudge for the current version so
    /// it won't reappear on the next foreground/launch.
    public func dismissSoftNudge() {
        guard case .softNudge(let latest, _) = gateState, let latest else { return }
        dismissedNudgeVersion = latest
        try? store.set(latest, forKey: Self.dismissedNudgeKey)
    }

    // MARK: - Caching

    private func cache(_ config: IOSAppConfig) {
        try? store.set(config, forKey: Self.cacheKey)
    }

    // MARK: - Debug overrides

    #if DEBUG
    /// Lets the four states be exercised in the simulator without a live backend,
    /// e.g. `--config-gate=hard`. Returns `nil` when no override is present.
    private static func debugForcedState() -> AppConfigGateState? {
        guard let arg = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--config-gate=") }) else { return nil }
        switch String(arg.dropFirst("--config-gate=".count)) {
        case "hard":
            return .hardGate(message: "A newer version of ChapterFlow is required to continue.")
        case "maintenance":
            return .maintenance(message: "ChapterFlow is down for scheduled maintenance. We'll be right back.")
        case "soft":
            return .softNudge(latestVersion: "99.0.0", message: nil)
        case "none":
            return AppConfigGateState.none
        default:
            return nil
        }
    }
    #endif
}
