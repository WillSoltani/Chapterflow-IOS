import Testing
import Foundation
@testable import AppFeature
import CoreKit
import Networking
import Persistence

// MARK: - Service (fetch / cache / fail-open)

@Suite("AppConfigService — fetch, cache, fail-open")
@MainActor
struct AppConfigServiceTests {

    private let appStoreID = "1234567890"
    private let appStoreURL = URL(string: "https://apps.apple.com/app/chapterflow/id1234567890")
    private let supportURL = URL(string: "https://support.chapterflow.test/help")

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

    private func service(
        client: MockAPIClient,
        store: KeyValueStore? = nil,
        includeAppStoreDestination: Bool = true,
        environment: AppEnvironment = .staging,
        apiBaseURL: String = "https://api.staging.chapterflow.test",
        cacheMaxAge: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) -> AppConfigService {
        AppConfigService(
            apiClient: client,
            currentVersion: "1.0.0",
            store: store ?? makeStore(),
            appStoreID: includeAppStoreDestination ? appStoreID : "",
            appStoreURL: includeAppStoreDestination ? appStoreURL : nil,
            supportURL: supportURL,
            environment: environment,
            apiBaseURL: apiBaseURL,
            cacheMaxAge: cacheMaxAge,
            now: now
        )
    }

    @Test("successful fetch below minimum shows the hard gate")
    func fetchHardGate() async {
        let client = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let service = service(client: client)
        await service.refresh()
        #expect(service.gateState == .hardGate(message: nil))
    }

    @Test("fetch failure with no cache fails open (.none)")
    func failOpenNoCache() async {
        let client = await mock(failure: true)
        let service = service(client: client)
        await service.refresh()
        #expect(service.gateState == .none)
    }

    @Test("fetch failure falls back to the last-good cached config (offline)")
    func failOpenUsesCache() async {
        let store = makeStore()

        // First: a successful fetch caches a hard-gate config.
        let good = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let first = service(client: good, store: store)
        await first.refresh()
        #expect(first.gateState == .hardGate(message: nil))

        // Then: a new service backed by the SAME store but a failing client must
        // seed from cache at init and keep the gate after a failed refresh.
        let bad = await mock(failure: true)
        let second = service(client: bad, store: store)
        #expect(second.gateState == .hardGate(message: nil)) // seeded from cache
        await second.refresh()
        #expect(second.gateState == .hardGate(message: nil)) // still gated after failure
    }

    @Test("cached config cannot cross environment or API-host boundaries")
    func cacheIsScopedToBuildAndAPIHost() async {
        let store = makeStore()
        let good = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let staging = service(client: good, store: store)
        await staging.refresh()
        #expect(staging.gateState == .hardGate(message: nil))

        let offline = await mock(failure: true)
        let production = service(
            client: offline,
            store: store,
            environment: .production,
            apiBaseURL: "https://api.chapterflow.test"
        )
        #expect(production.gateState == .none)
        await production.refresh()
        #expect(production.gateState == .none)

        let otherHost = service(
            client: offline,
            store: store,
            apiBaseURL: "https://other.staging.chapterflow.test"
        )
        #expect(otherHost.gateState == .none)
    }

    @Test("expired cached config fails open")
    func staleCacheFailsOpen() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 1_000)
        let good = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let first = service(
            client: good,
            store: store,
            cacheMaxAge: 60,
            now: { clock }
        )
        await first.refresh()
        #expect(first.gateState == .hardGate(message: nil))

        clock = clock.addingTimeInterval(61)
        let offline = await mock(failure: true)
        let second = service(
            client: offline,
            store: store,
            cacheMaxAge: 60,
            now: { clock }
        )
        #expect(second.gateState == .none)
        await second.refresh()
        #expect(second.gateState == .none)
    }

    @Test("soft nudge can be dismissed and stays dismissed")
    func softNudgeDismissal() async {
        let store = makeStore()
        let client = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let firstService = service(client: client, store: store)
        await firstService.refresh()
        #expect(firstService.gateState == .softNudge(latestVersion: "9.0.0", message: nil))
        #expect(firstService.shouldShowSoftNudge)

        firstService.dismissSoftNudge()
        #expect(!firstService.shouldShowSoftNudge)

        // A brand-new service (same store, same version) stays dismissed.
        let client2 = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let secondService = service(client: client2, store: store)
        await secondService.refresh()
        #expect(!secondService.shouldShowSoftNudge)
    }

    @Test("maintenance response shows the maintenance state")
    func maintenanceFetch() async {
        let client = await mock(config: IOSAppConfig(maintenanceMode: true, messageOfTheDay: "brb"))
        let service = service(client: client)
        await service.refresh()
        #expect(service.gateState == .maintenance(message: "brb"))
    }

    @Test("overlapping refresh calls share one network request")
    func refreshIsSingleFlight() async throws {
        let response = IOSAppConfig(latestVersion: "9.0.0")
        let data = try JSONCoding.encoder.encode(response)
        let client = DelayedConfigAPIClient(responseData: data)
        let service = AppConfigService(
            apiClient: client,
            currentVersion: "1.0.0",
            store: makeStore(),
            appStoreID: appStoreID,
            appStoreURL: appStoreURL,
            supportURL: supportURL,
            environment: .staging,
            apiBaseURL: "https://api.staging.chapterflow.test"
        )

        let first = Task { await service.refresh() }
        await client.waitForRequestStart()
        let second = Task { await service.refresh() }
        await first.value
        await second.value

        #expect(await client.requestCount() == 1)
        #expect(service.gateState == .softNudge(latestVersion: "9.0.0", message: nil))
    }

    @Test("uses an approved server URL and otherwise the compiled exact listing")
    func appStoreURLResolution() async {
        let localizedURL = "https://apps.apple.com/ca/app/chapterflow/id1234567890"
        let withURL = await mock(config: IOSAppConfig(latestVersion: "9.0.0", appStoreURL: localizedURL))
        let approvedService = service(client: withURL)
        await approvedService.refresh()
        #expect(approvedService.appStoreURL?.absoluteString == localizedURL)

        let wrongProduct = await mock(config: IOSAppConfig(
            latestVersion: "9.0.0",
            appStoreURL: "https://apps.apple.com/app/another-app/id9999999999"
        ))
        let fallbackService = service(client: wrongProduct)
        await fallbackService.refresh()
        #expect(fallbackService.appStoreURL == appStoreURL)
    }

    @Test("a hard gate without an exact listing becomes a supportable maintenance state")
    func hardGateRequiresExactDestination() async {
        let client = await mock(config: IOSAppConfig(minSupportedVersion: "5.0.0"))
        let service = service(client: client, includeAppStoreDestination: false)

        await service.refresh()

        guard case .maintenance(let message) = service.gateState else {
            Issue.record("Expected a maintenance fallback when the exact listing is unavailable")
            return
        }
        #expect(message?.contains("App Store listing") == true)
        #expect(service.appStoreURL == nil)
        #expect(service.supportURL == supportURL)
    }

    @Test("a soft nudge is hidden without an exact listing")
    func softNudgeRequiresExactDestination() async {
        let client = await mock(config: IOSAppConfig(latestVersion: "9.0.0"))
        let service = service(client: client, includeAppStoreDestination: false)

        await service.refresh()

        #expect(service.gateState == .softNudge(latestVersion: "9.0.0", message: nil))
        #expect(!service.shouldShowSoftNudge)
    }

    @Test(arguments: [
        "https://apps.apple.com/app/id1234567890",
        "https://apps.apple.com/app/id1234567890/",
        "https://apps.apple.com/ca/app/chapterflow/id1234567890",
        "itms-apps://itunes.apple.com/app/id1234567890"
    ])
    func acceptsExactAppStoreDestinations(_ rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(AppConfigService.isApprovedAppStoreURL(url, appStoreID: appStoreID))
    }

    @Test(arguments: [
        "https://apps.apple.com/search?term=ChapterFlow",
        "https://apps.apple.com/app/id9999999999",
        "https://apps.apple.com/app/id12345678901",
        "https://apps.apple.com/app/id1234567890?campaign=release",
        "https://apps.apple.com/app/id1234567890/reviews",
        "https://apps.apple.com:443/app/id1234567890",
        "https://user:password@apps.apple.com/app/id1234567890",
        "https://example.com/app/id1234567890",
        "http://apps.apple.com/app/id1234567890"
    ])
    func rejectsAmbiguousOrUnapprovedDestinations(_ rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(!AppConfigService.isApprovedAppStoreURL(url, appStoreID: appStoreID))
    }

    @Test("rejects a short numeric identifier")
    func rejectsShortAppStoreID() throws {
        let url = try #require(URL(string: "https://apps.apple.com/app/id12345"))
        #expect(!AppConfigService.isApprovedAppStoreURL(url, appStoreID: "12345"))
    }

    @Test("rejects an identifier with a leading zero")
    func rejectsLeadingZeroAppStoreID() throws {
        let url = try #require(URL(string: "https://apps.apple.com/app/id0123456789"))
        #expect(!AppConfigService.isApprovedAppStoreURL(url, appStoreID: "0123456789"))
    }
}

private actor DelayedConfigAPIClient: APIClientProtocol {
    private let responseData: Data
    private var sends = 0
    private var requestStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(responseData: Data) {
        self.responseData = responseData
    }

    func send<Value: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Value {
        sends += 1
        requestStarted = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        try await Task.sleep(for: .milliseconds(50))
        return try JSONCoding.decoder.decode(Value.self, from: responseData)
    }

    func sendData(_ endpoint: Endpoint) async throws -> Data {
        sends += 1
        return responseData
    }

    func waitForRequestStart() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func requestCount() -> Int { sends }
}
