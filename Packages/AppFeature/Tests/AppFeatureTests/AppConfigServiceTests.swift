import Testing
import Foundation
@testable import AppFeature
import Networking
import Persistence
// MARK: - Service (fetch / cache / fail-open)

@Suite("AppConfigService — fetch, cache, fail-open")
@MainActor
struct AppConfigServiceTests {

    private func makeStore() -> KeyValueStore {
        // A fresh, isolated UserDefaults suite per test avoids cross-test bleed.
        let suite = "test.appconfig.\(UUID().uuidString)"
        return KeyValueStore(defaults: UserDefaults(suiteName: suite))
    }

    private func mock(config: IOSAppConfig? = nil, failure: Bool = false) async -> MockAPIClient {
        let client = MockAPIClient()
        if failure {
            await client.setStub(.failure(.offline), for: "/book/config/ios")
        } else if let config {
            try? await client.setStub(config, for: "/book/config/ios")
        }
        return client
    }

    @Test("successful fetch below minimum shows the hard gate")
    func fetchHardGate() async {
        let client = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let service = AppConfigService(apiClient: client, currentVersion: "1.0.0", store: makeStore())
        await service.refresh()
        #expect(service.gateState == .hardGate(message: nil))
    }

    @Test("fetch failure with no cache fails open (.none)")
    func failOpenNoCache() async {
        let client = await mock(failure: true)
        let service = AppConfigService(apiClient: client, currentVersion: "1.0.0", store: makeStore())
        await service.refresh()
        #expect(service.gateState == .none)
    }

    @Test("fetch failure falls back to the last-good cached config (offline)")
    func failOpenUsesCache() async {
        let store = makeStore()

        // First: a successful fetch caches a hard-gate config.
        let good = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let first = AppConfigService(apiClient: good, currentVersion: "1.0.0", store: store)
        await first.refresh()
        #expect(first.gateState == .hardGate(message: nil))

        // Then: a new service backed by the SAME store but a failing client must
        // seed from cache at init and keep the gate after a failed refresh.
        let bad = await mock(failure: true)
        let second = AppConfigService(apiClient: bad, currentVersion: "1.0.0", store: store)
        #expect(second.gateState == .hardGate(message: nil)) // seeded from cache
        await second.refresh()
        #expect(second.gateState == .hardGate(message: nil)) // still gated after failure
    }

    @Test("soft nudge can be dismissed and stays dismissed")
    func softNudgeDismissal() async {
        let store = makeStore()
        let client = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let service = AppConfigService(apiClient: client, currentVersion: "1.0.0", store: store)
        await service.refresh()
        #expect(service.gateState == .softNudge(latestVersion: "9.0.0", message: nil))
        #expect(service.shouldShowSoftNudge)

        service.dismissSoftNudge()
        #expect(!service.shouldShowSoftNudge)

        // A brand-new service (same store, same version) stays dismissed.
        let client2 = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let service2 = AppConfigService(apiClient: client2, currentVersion: "1.0.0", store: store)
        await service2.refresh()
        #expect(!service2.shouldShowSoftNudge)
    }

    @Test("maintenance response shows the maintenance state")
    func maintenanceFetch() async {
        let client = await mock(config: IOSAppConfig(maintenanceMode: true, messageOfTheDay: "brb"))
        let service = AppConfigService(apiClient: client, currentVersion: "1.0.0", store: makeStore())
        await service.refresh()
        #expect(service.gateState == .maintenance(message: "brb"))
    }

    @Test("uses server appStoreURL when present, else the fallback")
    func appStoreURLResolution() async {
        let withURL = await mock(config: IOSAppConfig(latestVersion: "9.0.0", appStoreURL: "https://apps.apple.com/app/id42"))
        let service = AppConfigService(apiClient: withURL, currentVersion: "1.0.0", store: makeStore())
        await service.refresh()
        #expect(service.appStoreURL.absoluteString == "https://apps.apple.com/app/id42")

        let withoutURL = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let service2 = AppConfigService(apiClient: withoutURL, currentVersion: "1.0.0", store: makeStore())
        await service2.refresh()
        #expect(service2.appStoreURL == AppConfigService.fallbackAppStoreURL)
    }
}
