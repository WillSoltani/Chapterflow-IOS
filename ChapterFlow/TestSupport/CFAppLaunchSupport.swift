#if DEBUG
import AppFeature
import CoreKit
import Foundation

/// Entry point for XCUITest environment overrides applied at app launch.
///
/// Called from ``ChapterFlowApp.init()`` before any SwiftUI scene is constructed.
/// Four env-var flags drive the hermetic infrastructure:
///
/// - `CF_STUB_SERVER=1` → registers ``CFStubURLProtocol`` so every URLSession
///   request in the app process is served by fixture-backed stubs.
/// - `CF_UITEST_BYPASS_AUTH=1` → seeds the Keychain with a pre-built test JWT
///   so the app presents as signed-in without performing a real Cognito handshake.
/// - `CF_HERMETIC_TEST_CONFIGURATION=1` together with `CF_STUB_SERVER=1` →
///   selects a typed, non-production API/Cognito configuration.
/// - `CF_INVALID_TEST_CONFIGURATION=1` → selects committed-equivalent
///   placeholders so the fail-closed root can be exercised independently of a
///   developer's ignored `Secrets.xcconfig`.
///
/// All flags are harmless when absent; this file is stripped from release builds.
enum CFAppLaunchSupport {
    private static let hermeticConfigurationKey = "CF_HERMETIC_TEST_CONFIGURATION"
    private static let invalidConfigurationKey = "CF_INVALID_TEST_CONFIGURATION"
    private static let stubServerKey = "CF_STUB_SERVER"
    private static let suspendStorageKey = "CF_BOOTSTRAP_SUSPEND_STORAGE"
    private static let failStorageOnceKey = "CF_BOOTSTRAP_FAIL_STORAGE_ONCE"
    private static let failSessionKey = "CF_BOOTSTRAP_FAIL_SESSION"

    static func applyUITestOverrides() {
        let env = ProcessInfo.processInfo.environment

        if env[stubServerKey] == "1" {
            // URLProtocol.registerClass adds CFStubURLProtocol to the shared
            // configuration, intercepting all requests on URLSession.shared and
            // any session created from the default configuration (including Amplify).
            URLProtocol.registerClass(CFStubURLProtocol.self)
        }

        if env["CF_UITEST_BYPASS_AUTH"] == "1" {
            // Seed tokens BEFORE AppModel / AuthService initialise so the
            // auth state resolves as signed-in from the very first check.
            CFUITestSessionSeeder.seedIfNeeded()

            // Mark first-run onboarding complete so the app lands directly in the
            // main tab UI. Otherwise AppRootView presents OnboardingFlowView as a
            // full-screen cover (gated on `!preferences.onboardingCompleted`),
            // which blocks tab navigation and makes signed-in flow tests hang.
            // Key + suite mirror AppPreferences.Keys.onboardingCompleted + AppGroup.identifier.
            UserDefaults(suiteName: "group.com.chapterflow")?
                .set(true, forKey: "pref.onboardingCompleted")
        }
    }

    /// Returns a safe synthetic configuration only for the explicit hermetic
    /// XCUITest path. Requiring both flags prevents a normal Debug launch—or a
    /// smoke test using auth bypass alone—from activating it accidentally.
    static func resolveConfiguration(default defaultConfig: AppConfig) -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        if env[invalidConfigurationKey] == "1" {
            // This fixture is intentionally minimal. Validation stops before
            // service construction, so Sentry and StoreKit identities remain
            // explicitly empty rather than inheriting developer configuration.
            return AppConfig(
                apiBaseURL: "https://api.chapterflow.example.com",
                cognitoRegion: "us-east-1",
                cognitoUserPoolID: "us-east-1_XXXXXXXXX",
                cognitoClientID: "XXXXXXXXXXXXXXXXXXXXXXXXXX",
                cognitoDomain: "auth.your-domain.auth.us-east-1.amazoncognito.com",
                sentryDSN: "",
                storeKitMonthlyProductID: "",
                storeKitAnnualProductID: "",
                storeKitAnnualUpfrontProductID: ""
            )
        }

        guard env[stubServerKey] == "1",
              env[hermeticConfigurationKey] == "1" else {
            return defaultConfig
        }

        let requiredServices = AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowUITest",
            cognitoClientID: "chapterflowuitestclient12345",
            cognitoDomain: "auth.chapterflow.test"
        )
        return defaultConfig.applyingHermeticServiceOverlay(requiredServices)
    }

    /// Builds the production coordinator unless a bootstrap failure mode is
    /// explicitly requested inside the fully hermetic XCUITest boundary.
    static func makeBootstrap(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration
    ) -> AppBootstrapCoordinator {
        let env = ProcessInfo.processInfo.environment
        guard env[stubServerKey] == "1",
              env[hermeticConfigurationKey] == "1" else {
            return AppBootstrapCoordinator(
                config: config,
                buildConfiguration: buildConfiguration
            )
        }

        let mode: AppBootstrapDebugMode
        if env[suspendStorageKey] == "1" {
            mode = .suspendStorage
        } else if env[failStorageOnceKey] == "1" {
            mode = .failStorageOnce
        } else if env[failSessionKey] == "1" {
            mode = .failSessionConfiguration
        } else {
            mode = .live
        }

        return AppBootstrapCoordinator(
            config: config,
            buildConfiguration: buildConfiguration,
            debugMode: mode
        )
    }
}
#endif
