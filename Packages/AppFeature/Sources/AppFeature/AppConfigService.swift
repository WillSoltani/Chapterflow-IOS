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

    /// The exact, product-specific App Store destination approved by the build.
    ///
    /// A backend value may refine the storefront path, but only when it names
    /// the same numeric App Store product. Search URLs and URLs for another app
    /// are rejected. `nil` intentionally prevents a hard update gate from being
    /// presented with an unusable or ambiguous destination.
    public var appStoreURL: URL? {
        if let raw = config?.appStoreURL,
           let remoteURL = URL(string: raw),
           Self.isApprovedAppStoreURL(remoteURL, appStoreID: appStoreID) {
            return remoteURL
        }
        return compiledAppStoreURL
    }

    /// Product support remains reachable when opening the App Store fails.
    public let supportURL: URL?

    /// Whether the soft "update available" nudge should currently be shown: true
    /// only when the state is `.softNudge` and the user hasn't already dismissed
    /// the nudge for that specific version.
    public var shouldShowSoftNudge: Bool {
        guard appStoreURL != nil else { return false }
        guard case .softNudge(let latest, _) = gateState else { return false }
        return dismissedNudgeVersion == nil || dismissedNudgeVersion != latest
    }

    // MARK: - Dependencies

    private let apiClient: any APIClientProtocol
    private let currentVersion: String
    private let store: KeyValueStore
    private let appStoreID: String
    private let compiledAppStoreURL: URL?
    private let cacheScope: String
    private let cacheMaxAge: TimeInterval
    private let now: () -> Date
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private static let cacheSchemaVersion = 1

    /// The App Store version for which the user tapped "Later" on the soft nudge,
    /// so it doesn't re-nag on every foreground. Persisted across launches.
    private var dismissedNudgeVersion: String?

    // MARK: - Init

    public init(
        apiClient: any APIClientProtocol,
        currentVersion: String? = nil,
        store: KeyValueStore = KeyValueStore(),
        appStoreID: String = "",
        appStoreURL: URL? = nil,
        supportURL: URL? = nil,
        environment: AppEnvironment = .unknown,
        apiBaseURL: String = "",
        cacheMaxAge: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.apiClient = apiClient
        // `Bundle.appShortVersion` is module-internal, so it can't be a default
        // argument on this public init — resolve it here instead.
        let version = currentVersion ?? Bundle.main.appShortVersion
        self.currentVersion = version
        self.store = store
        self.appStoreID = appStoreID
        self.cacheScope = Self.makeCacheScope(environment: environment, apiBaseURL: apiBaseURL)
        self.cacheMaxAge = cacheMaxAge
        self.now = now
        self.compiledAppStoreURL = appStoreURL.flatMap { url in
            Self.isApprovedAppStoreURL(url, appStoreID: appStoreID) ? url : nil
        }
        self.supportURL = supportURL
        self.dismissedNudgeVersion = store.value(String.self, forKey: dismissedNudgeKey)
        // Seed synchronously from any cached config so a blocking gate is honoured
        // instantly at launch, before the network round-trip completes.
        if let cached = validCachedConfig() {
            self.config = cached
            self.gateState = resolvedGateState(for: cached)
        }
    }

    // MARK: - Refresh

    /// Fetches the latest config and recomputes the gate. Call at launch and on
    /// every foreground activation. Never throws — failures fail open.
    public func refresh() async {
        #if DEBUG
        if let forced = Self.debugForcedState() {
            gateState = resolvedGateState(for: forced)
            return
        }
        #endif
        if let refreshTask {
            await refreshTask.value
            return
        }

        let apiClient = apiClient
        let task = Task { @MainActor [weak self] in
            do {
                let fresh: IOSAppConfig = try await apiClient.send(Endpoints.getIOSConfig())
                guard !Task.isCancelled, let self else { return }
                self.cache(fresh)
                self.config = fresh
                self.gateState = self.resolvedGateState(for: fresh)
            } catch {
                guard !Task.isCancelled, let self else { return }
                // FAIL OPEN: fall back to last-good cached config (or none). A fetch
                // failure must never introduce a lock the server didn't ask for.
                let cached = self.validCachedConfig()
                self.config = cached
                self.gateState = self.resolvedGateState(for: cached)
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Records that the user dismissed the soft nudge for the current version so
    /// it won't reappear on the next foreground/launch.
    public func dismissSoftNudge() {
        guard case .softNudge(let latest, _) = gateState, let latest else { return }
        dismissedNudgeVersion = latest
        try? store.set(latest, forKey: dismissedNudgeKey)
    }

    // MARK: - Caching

    private func cache(_ config: IOSAppConfig) {
        let cached = CachedIOSAppConfig(
            schemaVersion: Self.cacheSchemaVersion,
            scope: cacheScope,
            fetchedAt: now(),
            config: config
        )
        try? store.set(cached, forKey: cacheKey)
    }

    private func validCachedConfig() -> IOSAppConfig? {
        guard let cached = store.value(CachedIOSAppConfig.self, forKey: cacheKey),
              cached.schemaVersion == Self.cacheSchemaVersion,
              cached.scope == cacheScope
        else { return nil }

        let age = now().timeIntervalSince(cached.fetchedAt)
        guard age >= 0, age <= cacheMaxAge else {
            store.removeValue(forKey: cacheKey)
            return nil
        }
        return cached.config
    }

    private var cacheKey: String {
        "appConfig.lastGood.v\(Self.cacheSchemaVersion).\(cacheScope)"
    }

    private var dismissedNudgeKey: String {
        "appConfig.dismissedNudgeVersion.\(cacheScope)"
    }

    private static func makeCacheScope(environment: AppEnvironment, apiBaseURL: String) -> String {
        let host = URL(string: apiBaseURL)?.host?.lowercased() ?? "invalid-host"
        return "\(environment.rawValue).\(host)"
    }

    // MARK: - Destination validation

    private func resolvedGateState(for config: IOSAppConfig?) -> AppConfigGateState {
        resolvedGateState(for: AppConfigGate.evaluate(config: config, currentVersion: currentVersion))
    }

    private func resolvedGateState(for state: AppConfigGateState) -> AppConfigGateState {
        guard case .hardGate = state, appStoreURL == nil else { return state }
        return .maintenance(
            message: "An update is required, but the App Store listing is temporarily unavailable. Please contact support."
        )
    }

    static func isApprovedAppStoreURL(_ url: URL, appStoreID: String) -> Bool {
        guard !appStoreID.isEmpty,
              (6...20).contains(appStoreID.count),
              appStoreID.first != "0",
              appStoreID.allSatisfy(\.isNumber),
              let components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "itms-apps",
              let host = url.host?.lowercased(),
              host == "apps.apple.com" || host == "itunes.apple.com"
        else { return false }

        let expectedComponent = "id\(appStoreID)"
        return url.pathComponents.last == expectedComponent
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

private struct CachedIOSAppConfig: Codable, Sendable {
    let schemaVersion: Int
    let scope: String
    let fetchedAt: Date
    let config: IOSAppConfig
}
