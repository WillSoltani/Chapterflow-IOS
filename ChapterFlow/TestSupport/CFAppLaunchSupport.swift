#if DEBUG
import Foundation

/// Entry point for XCUITest environment overrides applied at app launch.
///
/// Called from ``ChapterFlowApp.init()`` before any SwiftUI scene is constructed.
/// Two env-var flags drive the stub infrastructure:
///
/// - `CF_STUB_SERVER=1` → registers ``CFStubURLProtocol`` so every URLSession
///   request in the app process is served by fixture-backed stubs.
/// - `CF_UITEST_BYPASS_AUTH=1` → seeds the Keychain with a pre-built test JWT
///   so the app presents as signed-in without performing a real Cognito handshake.
///
/// Both flags are harmless when absent; this file is stripped from release builds.
enum CFAppLaunchSupport {
    static func applyUITestOverrides() {
        let env = ProcessInfo.processInfo.environment

        if env["CF_STUB_SERVER"] == "1" {
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
}
#endif
