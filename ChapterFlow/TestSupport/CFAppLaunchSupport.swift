#if DEBUG
import Foundation
import CoreKit

/// Entry point for XCUITest environment overrides applied at app launch.
///
/// Called from ``ChapterFlowApp.init()`` before any SwiftUI scene is constructed.
/// Four env-var flags drive the stub infrastructure:
///
/// - `CF_STUB_SERVER=1` → registers ``CFStubURLProtocol`` so every URLSession
///   request in the app process is served by fixture-backed stubs.
/// - `CF_UITEST_BYPASS_AUTH=1` → seeds the Keychain with a pre-built test JWT
///   so the app presents as signed-in without performing a real Cognito handshake.
/// - `CF_UITEST_INVALID_CONFIG=1` → injects a deliberately invalid local
///   configuration so UI tests can prove the fail-closed bootstrap surface.
/// - `CF_UITEST_DEFER_APPLE_VERIFY_UNTIL_RESTORE=1` → keeps every automatic
///   post-relaunch Apple verification free until the UI test signals that the
///   user explicitly selected Restore Purchases.
///
/// All flags are harmless when absent; this file is stripped from release builds.
enum CFAppLaunchSupport {
    private enum EnvironmentKey {
        static let stubServer = "CF_STUB_SERVER"
        static let bypassAuth = "CF_UITEST_BYPASS_AUTH"
        static let invalidConfiguration = "CF_UITEST_INVALID_CONFIG"
    }

    private enum TestConfiguration {
        static let appStoreID = "6787864558"
        static let appStoreURL = "https://apps.apple.com/app/id6787864558"
        static let supportURL = "https://support.chapterflow.com/help"
        static let monthlyProductID = "com.chapterflow.pro.monthly"
        static let annualProductID = "com.chapterflow.pro.annual"
    }

    /// Deterministic, nonproduction configuration for fixture-backed UI tests.
    /// It passes the same typed validator as a normal build; this is not a
    /// validation bypass and is compiled out of Release builds.
    static var configurationOverride: AppConfig? {
        let environment = ProcessInfo.processInfo.environment
        if environment[EnvironmentKey.invalidConfiguration] == "1" {
            return makeConfiguration(apiBaseURL: "")
        }
        guard environment[EnvironmentKey.stubServer] == "1" else {
            return nil
        }
        return makeConfiguration(apiBaseURL: "https://stub.chapterflow.internal")
    }

    private static func makeConfiguration(apiBaseURL: String) -> AppConfig {
        return AppConfig(
            apiBaseURL: apiBaseURL,
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_UITestPool",
            cognitoClientID: "UITestClient123",
            cognitoDomain: "auth.chapterflow.internal",
            storeKitMonthlyProductID: TestConfiguration.monthlyProductID,
            storeKitAnnualProductID: TestConfiguration.annualProductID,
            environment: .development,
            bundleIdentifier: "com.chapterflow.ios",
            appStoreID: TestConfiguration.appStoreID,
            appStoreURL: TestConfiguration.appStoreURL,
            supportURL: TestConfiguration.supportURL,
            sentryPolicy: .disabled,
            buildConfiguration: "Debug",
            buildCommitSHA: "0000000",
            marketingVersion: "1.0",
            buildNumber: "1"
        )
    }

    static func applyUITestOverrides() {
        let env = ProcessInfo.processInfo.environment

        if env[EnvironmentKey.stubServer] == "1" {
            CFStubRoutes.reset()
            // URLProtocol.registerClass adds CFStubURLProtocol to the shared
            // configuration, intercepting all requests on URLSession.shared and
            // any session created from the default configuration (including Amplify).
            URLProtocol.registerClass(CFStubURLProtocol.self)
        }

        if env[EnvironmentKey.bypassAuth] == "1" {
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
}
#endif
