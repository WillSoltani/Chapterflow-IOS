import Testing
@testable import CoreKit

@MainActor
@Suite("FeatureFlags")
struct FeatureFlagsTests {
    @Test("falls back to built-in defaults before any fetch")
    func defaultsBeforeFetch() {
        let flags = FeatureFlags()
        #expect(flags.config == nil)
        #expect(flags.isEnabled(.offlineReading) == FeatureFlags.Flag.offlineReading.defaultValue)
        #expect(flags.isEnabled(.aiTutor) == false)      // risky surface, dark-launched off
        #expect(flags.isEnabled(.referrals) == true)     // stable, on by default
    }

    @Test("unknown string keys default to false")
    func unknownKey() {
        let flags = FeatureFlags()
        #expect(flags.isEnabled("totally_unknown_flag") == false)
    }

    @Test("applying remote config overrides only the keys it names")
    func remoteOverride() {
        let flags = FeatureFlags()
        #expect(flags.isEnabled(.aiTutor) == false)

        let config = IOSConfig(
            minSupportedVersion: "1.0.0",
            latestVersion: "1.2.0",
            featureFlags: ["ai_tutor": true],   // enable a previously-off flag
            storeKitProductIds: ["com.chapterflow.pro.annual"],
            maintenanceMode: false,
            messageOfTheDay: nil
        )
        flags.apply(config)

        #expect(flags.config == config)
        #expect(flags.isEnabled(.aiTutor) == true)                 // overridden
        #expect(flags.isEnabled(.referrals) == true)               // untouched → default
        #expect(flags.isEnabled(.offlineReading) == true)          // untouched → default
    }

    @Test("reset restores defaults and clears config")
    func reset() {
        let flags = FeatureFlags()
        flags.apply(IOSConfig(
            minSupportedVersion: "1.0.0",
            latestVersion: "1.0.0",
            featureFlags: ["ai_tutor": true],
            storeKitProductIds: [],
            maintenanceMode: false,
            messageOfTheDay: nil
        ))
        #expect(flags.isEnabled(.aiTutor) == true)

        flags.reset()
        #expect(flags.config == nil)
        #expect(flags.isEnabled(.aiTutor) == false)
    }

    @Test("built-in defaults cover every known flag")
    func defaultsCoverAllFlags() {
        for flag in FeatureFlags.Flag.allCases {
            #expect(FeatureFlags.builtInDefaults[flag.rawValue] == flag.defaultValue)
        }
    }
}
