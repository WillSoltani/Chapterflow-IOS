import Testing
import Foundation
@testable import Networking

@Suite("IOSAppConfig — tolerant decoding (RF2)")
struct IOSAppConfigTests {

    private func decode(_ json: String) throws -> IOSAppConfig {
        try JSONCoding.decoder.decode(IOSAppConfig.self, from: Data(json.utf8))
    }

    @Test("endpoint is public and correct")
    func endpointShape() {
        let endpoint = Endpoints.getIOSConfig()
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/book/config/ios")
        #expect(endpoint.requiresAuth == false)
    }

    @Test("decodes the full documented shape")
    func fullShape() throws {
        let config = try decode(#"""
        {
          "minSupportedVersion": "2.0.0",
          "latestVersion": "2.4.1",
          "featureFlags": {"audio": true, "social": false},
          "storeKitProductIds": ["cf.monthly", "cf.annual"],
          "maintenanceMode": false,
          "messageOfTheDay": "Welcome back",
          "appStoreURL": "https://apps.apple.com/app/id123"
        }
        """#)
        #expect(config.minSupportedVersion == "2.0.0")
        #expect(config.latestVersion == "2.4.1")
        #expect(config.featureFlags["audio"] == true)
        #expect(config.featureFlags["social"] == false)
        #expect(config.storeKitProductIds == ["cf.monthly", "cf.annual"])
        #expect(config.maintenanceMode == false)
        #expect(config.messageOfTheDay == "Welcome back")
        #expect(config.appStoreURL == "https://apps.apple.com/app/id123")
    }

    @Test("empty object decodes to all-defaults (never throws)")
    func emptyObject() throws {
        let config = try decode("{}")
        #expect(config.minSupportedVersion == nil)
        #expect(config.latestVersion == nil)
        #expect(config.featureFlags.isEmpty)
        #expect(config.storeKitProductIds.isEmpty)
        #expect(config.maintenanceMode == false)
        #expect(config.messageOfTheDay == nil)
        #expect(config.appStoreURL == nil)
    }

    @Test("extra/unknown keys are ignored")
    func extraKeys() throws {
        let config = try decode(#"""
        {"maintenanceMode": true, "futureField": {"nested": 1}, "status": "degraded"}
        """#)
        #expect(config.maintenanceMode == true)
    }

    @Test("null fields decode to nil / defaults")
    func nullFields() throws {
        let config = try decode(#"""
        {"minSupportedVersion": null, "maintenanceMode": null, "featureFlags": null}
        """#)
        #expect(config.minSupportedVersion == nil)
        #expect(config.maintenanceMode == false)
        #expect(config.featureFlags.isEmpty)
    }

    @Test("wrong types for individual fields fall back to defaults, not a throw")
    func wrongTypes() throws {
        // maintenanceMode as a string, minSupportedVersion as a number,
        // featureFlags as an array — none of these should crash decoding.
        let config = try decode(#"""
        {"maintenanceMode": "yes", "minSupportedVersion": 2, "featureFlags": [1,2,3], "latestVersion": "2.5.0"}
        """#)
        #expect(config.maintenanceMode == false)
        #expect(config.minSupportedVersion == nil)
        #expect(config.featureFlags.isEmpty)
        // A well-typed sibling field still decodes correctly.
        #expect(config.latestVersion == "2.5.0")
    }

    @Test("round-trips through Codable for offline caching")
    func roundTrip() throws {
        let original = IOSAppConfig(
            minSupportedVersion: "2.0.0",
            latestVersion: "2.4.0",
            featureFlags: ["audio": true],
            storeKitProductIds: ["cf.monthly"],
            maintenanceMode: true,
            messageOfTheDay: "hi",
            appStoreURL: "https://apps.apple.com"
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(IOSAppConfig.self, from: data)
        #expect(restored == original)
    }
}
