import Foundation
import SwiftUI
import CoreKit
import Networking

/// The app's dependency-injection container.
///
/// A single `Dependencies` value is built once at launch (``live()``) and
/// injected into the SwiftUI environment at the root. Feature views read it via
/// `@Environment(\.dependencies)` and hand the pieces they need to their
/// `@Observable` models through initializers (constructor injection). There is
/// no DI framework — this struct *is* the container.
///
/// New collaborators (repositories, `DownloadManager`, `SyncEngine`, …) are added
/// as properties here as each feature comes online. Everything held is either a
/// value type, an actor, or a `@MainActor @Observable` object, so the container
/// is safe to pass around and to store in the environment.
@MainActor
public struct Dependencies {
    /// Static configuration (API base URL, Cognito ids) from `Info.plist`.
    public let config: AppConfig
    /// The typed async API client. A protocol existential so previews/tests can
    /// substitute `MockAPIClient`.
    public let api: any APIClientProtocol
    /// Supplies/refreshes the Cognito `id_token` for authenticated requests.
    public let tokenStore: any TokenProviding
    /// User preferences (theme, reading tone/depth, …).
    public let preferences: AppPreferences
    /// Fire-and-forget analytics sink.
    public let analytics: any AnalyticsClient
    /// Remote-config-backed feature flags with safe local defaults.
    public let featureFlags: FeatureFlags

    public init(
        config: AppConfig,
        api: any APIClientProtocol,
        tokenStore: any TokenProviding,
        preferences: AppPreferences,
        analytics: any AnalyticsClient,
        featureFlags: FeatureFlags
    ) {
        self.config = config
        self.api = api
        self.tokenStore = tokenStore
        self.preferences = preferences
        self.analytics = analytics
        self.featureFlags = featureFlags
    }
}

// MARK: - Factories

public extension Dependencies {
    /// Builds the real container used by the shipping app.
    ///
    /// Reads `AppConfig` from the bundle's `Info.plist`, then wires the real
    /// `APIClient` against a token store. Until AuthKit (P1) lands, the token
    /// store is a ``StubTokenStore`` seeded with a placeholder token so the app
    /// boots straight into the tab shell; analytics is a no-op to avoid network
    /// chatter before there's a real session.
    static func live(bundle: Bundle = .main) -> Dependencies {
        let config = AppConfig.fromInfoPlist(bundle)
        let tokenStore = StubTokenStore(token: "stub-id-token")
        let baseURL = URL(string: config.apiBaseURL) ?? URL(string: "https://invalid.local")!
        let api = APIClient(
            baseURL: baseURL,
            tokenProvider: tokenStore,
            logger: DebugRequestLogger()
        )
        return Dependencies(
            config: config,
            api: api,
            tokenStore: tokenStore,
            preferences: AppPreferences(),
            analytics: NoopAnalyticsClient(),
            featureFlags: FeatureFlags()
        )
    }

    /// A fully in-memory container for previews and unit tests.
    ///
    /// Uses `MockAPIClient` and a `StubTokenStore` (signed-in by default). Pass
    /// `signedIn: false` to exercise the signed-out launch path.
    static func mock(signedIn: Bool = true) -> Dependencies {
        Dependencies(
            config: AppConfig(
                apiBaseURL: "https://example.com",
                cognitoRegion: "us-east-1",
                cognitoUserPoolID: "pool",
                cognitoClientID: "client"
            ),
            api: MockAPIClient(),
            tokenStore: StubTokenStore(token: signedIn ? "mock-id-token" : nil),
            preferences: AppPreferences(),
            analytics: NoopAnalyticsClient(),
            featureFlags: FeatureFlags()
        )
    }
}

// MARK: - Environment

private struct DependenciesKey: EnvironmentKey {
    /// The environment default is only ever read while a `View` body evaluates,
    /// which is on the main actor — so assuming main-actor isolation here is
    /// safe. In practice the root always injects a real value, so this default
    /// is a safety net rather than a value the app relies on.
    static var defaultValue: Dependencies {
        MainActor.assumeIsolated { Dependencies.mock() }
    }
}

public extension EnvironmentValues {
    /// The app's dependency container. Injected at the root; read by features.
    var dependencies: Dependencies {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}
