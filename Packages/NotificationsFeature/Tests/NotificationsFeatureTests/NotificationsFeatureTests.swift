import Testing
@testable import NotificationsFeature
import CoreKit
import Networking
import Foundation

private actor SuspendedDeviceRegistrationRepository: DeviceRegistrationRepository {
    private var registerContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var unregisteredTokens: [String] = []

    func register(apnsToken: String) async throws {
        _ = apnsToken
        await withCheckedContinuation { continuation in
            registerContinuation = continuation
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        try Task.checkCancellation()
    }

    func unregister(apnsToken: String) async throws {
        unregisteredTokens.append(apnsToken)
    }

    func waitUntilRegistrationStarts() async {
        if registerContinuation != nil { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeRegistration() {
        registerContinuation?.resume()
        registerContinuation = nil
    }

    func unregisteredTokenValues() -> [String] {
        unregisteredTokens
    }
}

// MARK: - Module smoke test

@Suite("NotificationsFeature")
struct ModuleTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(NotificationsFeature.moduleName == "NotificationsFeature")
    }
}

// MARK: - Data.apnsHex

@Suite("Data.apnsHex")
struct ApnsHexTests {

    @Test("single byte encodes to two-digit lowercase hex")
    func singleByte() {
        let data = Data([0x0F])
        #expect(data.apnsHex == "0f")
    }

    @Test("zero byte encodes correctly")
    func zeroByte() {
        let data = Data([0x00])
        #expect(data.apnsHex == "00")
    }

    @Test("max byte encodes correctly")
    func maxByte() {
        let data = Data([0xFF])
        #expect(data.apnsHex == "ff")
    }

    @Test("multi-byte token encodes as concatenated lowercase hex")
    func multipleBytes() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(data.apnsHex == "deadbeef")
    }

    @Test("32-byte APNs token produces 64 character hex string")
    func thirtyTwoByteToken() {
        let data = Data(repeating: 0xAB, count: 32)
        #expect(data.apnsHex.count == 64)
    }

    @Test("empty data produces empty string")
    func emptyData() {
        #expect(Data().apnsHex == "")
    }
}

// MARK: - DeviceRegistrationRepository

@Suite("DeviceRegistrationRepository")
struct DeviceRegistrationRepositoryTests {

    @Test("register appends token to registeredTokens")
    func registerRecordsToken() async throws {
        let repo = FakeDeviceRegistrationRepository()
        try await repo.register(apnsToken: "abc123")
        #expect(repo.registeredTokens == ["abc123"])
    }

    @Test("unregister appends token to unregisteredTokens")
    func unregisterRecordsToken() async throws {
        let repo = FakeDeviceRegistrationRepository()
        try await repo.unregister(apnsToken: "abc123")
        #expect(repo.unregisteredTokens == ["abc123"])
    }

    @Test("multiple registers accumulate all tokens")
    func multipleRegisters() async throws {
        let repo = FakeDeviceRegistrationRepository()
        try await repo.register(apnsToken: "token1")
        try await repo.register(apnsToken: "token2")
        #expect(repo.registeredTokens == ["token1", "token2"])
    }

    @Test("fake propagates registration and unregistration failures")
    func failuresPropagate() async {
        let repo = FakeDeviceRegistrationRepository()
        repo.shouldFailRegistration = true
        await #expect(throws: AppError.self) {
            try await repo.register(apnsToken: "token")
        }
        repo.shouldFailUnregistration = true
        await #expect(throws: AppError.self) {
            try await repo.unregister(apnsToken: "token")
        }
    }

    @Test("live registration propagates backend failure")
    func liveRegistrationPropagatesFailure() async {
        let client = MockAPIClient()
        await client.setStub(.failure(.offline), for: "/book/me/devices/register")
        let repo = LiveDeviceRegistrationRepository(apiClient: client)

        await #expect(throws: AppError.self) {
            try await repo.register(apnsToken: "token")
        }
    }

    @Test("live unregistration propagates backend failure")
    func liveUnregistrationPropagatesFailure() async {
        let client = MockAPIClient()
        await client.setStub(.failure(.offline), for: "/book/me/devices/unregister")
        let repo = LiveDeviceRegistrationRepository(apiClient: client)

        await #expect(throws: AppError.self) {
            try await repo.unregister(apnsToken: "token")
        }
    }
}

// MARK: - APNSRegistrationManager de-duplication

@Suite("APNSRegistrationManager — session lifecycle", .serialized)
@MainActor
struct APNSRegistrationManagerDedupTests {

    static let legacyDefaultsKey = "com.chapterflow.apnsLastRegisteredToken"

    func makeManager(
        defaults: UserDefaults = .standard,
        repo: FakeDeviceRegistrationRepository = .init(),
        authorizer: MockNotificationAuthorizer = .init(),
        storageNamespace: String = "account-a"
    ) -> (APNSRegistrationManager, FakeDeviceRegistrationRepository) {
        let manager = APNSRegistrationManager(
            authorizer: authorizer,
            repository: repo,
            storageNamespace: storageNamespace,
            defaults: defaults
        )
        return (manager, repo)
    }

    @Test("same token is not re-registered")
    func sameTokenSkipsRegistration() async {
        let defaults = UserDefaults(suiteName: "test-apns-dedup-same")!
        let (manager, repo) = makeManager(defaults: defaults)
        manager.start()
        defer { manager.stopAndReset() }

        let tokenData = Data([0x01, 0x02, 0x03])
        // Register once
        await manager.handleTokenReceived(tokenData)
        // Register again with same token
        await manager.handleTokenReceived(tokenData)

        #expect(repo.registeredTokens.count == 1)
        defaults.removePersistentDomain(forName: "test-apns-dedup-same")
    }

    @Test("different token unregisters old and registers new")
    func differentTokenRotates() async {
        let defaults = UserDefaults(suiteName: "test-apns-dedup-rotate")!
        let (manager, repo) = makeManager(defaults: defaults)
        manager.start()
        defer { manager.stopAndReset() }

        let token1 = Data([0x01, 0x02])
        let token2 = Data([0x03, 0x04])

        await manager.handleTokenReceived(token1)
        await manager.handleTokenReceived(token2)

        #expect(repo.registeredTokens.count == 2)
        #expect(repo.unregisteredTokens.count == 1)
        #expect(repo.unregisteredTokens.first == token1.apnsHex)
        defaults.removePersistentDomain(forName: "test-apns-dedup-rotate")
    }

    @Test("handleSignOut clears scoped token only after acknowledgement")
    func signOutClearsToken() async {
        let defaults = UserDefaults(suiteName: "test-apns-signout")!
        let (manager, repo) = makeManager(defaults: defaults)
        manager.start()
        await manager.handleTokenReceived(Data([0xAA]))

        let result = await manager.handleSignOut()

        #expect(result == .unregistered)
        #expect(repo.unregisteredTokens == ["aa"])
        #expect(manager.storedToken == nil)
        manager.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-signout")
    }

    @Test("handleSignOut is a no-op when no token is stored")
    func signOutWithNoStoredToken() async {
        let defaults = UserDefaults(suiteName: "test-apns-signout-empty")!
        let (manager, repo) = makeManager(defaults: defaults)

        let result = await manager.handleSignOut()

        #expect(result == .noRegisteredToken)
        #expect(repo.unregisteredTokens.isEmpty)
        defaults.removePersistentDomain(forName: "test-apns-signout-empty")
    }

    @Test("registration error is set on failed registration")
    func registrationErrorTracked() {
        let (manager, _) = makeManager()
        let error = URLError(.notConnectedToInternet)
        manager.handleRegistrationFailed(error)
        #expect(manager.registrationError != nil)
    }

    @Test("registration error is cleared on successful token receipt")
    func errorClearedOnSuccess() async {
        let defaults = UserDefaults(suiteName: "test-apns-error-clear")!
        let (manager, _) = makeManager(defaults: defaults)
        manager.start()
        defer { manager.stopAndReset() }

        manager.handleRegistrationFailed(URLError(.notConnectedToInternet))
        #expect(manager.registrationError != nil)

        await manager.handleTokenReceived(Data([0xAA, 0xBB]))
        #expect(manager.registrationError == nil)
        defaults.removePersistentDomain(forName: "test-apns-error-clear")
    }

    @Test("repeated start is idempotent")
    func repeatedStartIsIdempotent() async {
        let authorizer = MockNotificationAuthorizer()
        let (manager, _) = makeManager(authorizer: authorizer)
        manager.start()
        manager.start()
        await manager.waitForPendingOperations()

        #expect(authorizer.currentStatusCallCount == 1)
        manager.stopAndReset()
    }

    @Test("failed registration is surfaced and never persisted")
    func failedRegistrationIsNotPersisted() async {
        let defaults = UserDefaults(suiteName: "test-apns-register-failure")!
        let repo = FakeDeviceRegistrationRepository()
        repo.shouldFailRegistration = true
        let (manager, _) = makeManager(defaults: defaults, repo: repo)
        manager.start()

        await manager.handleTokenReceived(Data([0xAB]))

        #expect(manager.storedToken == nil)
        #expect(manager.registrationError is APNSRegistrationError)
        manager.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-register-failure")
    }

    @Test("failed sign-out unregister retains scoped token")
    func failedSignOutRetainsToken() async {
        let defaults = UserDefaults(suiteName: "test-apns-unregister-failure")!
        let repo = FakeDeviceRegistrationRepository()
        let (manager, _) = makeManager(defaults: defaults, repo: repo)
        manager.start()
        await manager.handleTokenReceived(Data([0xCD]))
        repo.shouldFailUnregistration = true

        let result = await manager.handleSignOut()

        #expect(result == .unregistrationFailed)
        #expect(manager.storedToken == "cd")
        manager.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-unregister-failure")
    }

    @Test("sign-out waits for an acknowledged in-flight registration")
    func signOutAwaitsInflightRegistration() async {
        let suiteName = "test-apns-inflight-signout"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = SuspendedDeviceRegistrationRepository()
        let authorizer = MockNotificationAuthorizer()
        let manager = APNSRegistrationManager(
            authorizer: authorizer,
            repository: repo,
            storageNamespace: "account-a",
            defaults: defaults
        )
        manager.start()
        APNSRegistrationBridge.shared.didReceiveToken(Data([0xFE]))
        await repo.waitUntilRegistrationStarts()

        let signOutTask = Task { await manager.handleSignOut() }
        while !manager.isPausedForTesting {
            await Task.yield()
        }
        await repo.resumeRegistration()
        let result = await signOutTask.value
        let unregisteredTokens = await repo.unregisteredTokenValues()

        #expect(result == .unregistered)
        #expect(unregisteredTokens == ["fe"])
        #expect(manager.storedToken == nil)
        manager.stopAndReset()
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("pause detaches token delivery and resume restores it")
    func pauseAndResume() async {
        let defaults = UserDefaults(suiteName: "test-apns-pause-resume")!
        let (manager, repo) = makeManager(defaults: defaults)
        manager.start()
        await manager.waitForPendingOperations()
        APNSRegistrationBridge.shared.didReceiveToken(Data([0x01]))
        await manager.waitForPendingOperations()

        manager.pause()
        APNSRegistrationBridge.shared.didReceiveToken(Data([0x02]))
        await manager.waitForPendingOperations()
        #expect(repo.registeredTokens == ["01"])

        manager.resume()
        APNSRegistrationBridge.shared.didReceiveToken(Data([0x02]))
        await manager.waitForPendingOperations()
        #expect(repo.registeredTokens == ["01", "02"])

        manager.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-pause-resume")
    }

    @Test("account namespaces isolate tokens")
    func accountNamespacesIsolateTokens() async {
        let defaults = UserDefaults(suiteName: "test-apns-account-isolation")!
        let (managerA, _) = makeManager(defaults: defaults, storageNamespace: "account-a")
        let (managerB, _) = makeManager(defaults: defaults, storageNamespace: "account-b")
        managerA.start()
        managerB.start()

        await managerA.handleTokenReceived(Data([0x0A]))
        await managerB.handleTokenReceived(Data([0x0B]))

        #expect(managerA.storedToken == "0a")
        #expect(managerB.storedToken == "0b")
        managerA.stopAndReset()
        managerB.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-account-isolation")
    }

    @Test("legacy global token is ignored and preserved")
    func legacyTokenIsQuarantined() async {
        let defaults = UserDefaults(suiteName: "test-apns-legacy-token")!
        defaults.set("legacy-token", forKey: Self.legacyDefaultsKey)
        let (manager, repo) = makeManager(defaults: defaults)

        let result = await manager.handleSignOut()

        #expect(result == .noRegisteredToken)
        #expect(repo.unregisteredTokens.isEmpty)
        #expect(defaults.string(forKey: Self.legacyDefaultsKey) == "legacy-token")
        manager.stopAndReset()
        defaults.removePersistentDomain(forName: "test-apns-legacy-token")
    }
}

// MARK: - Endpoints

@Suite("Endpoints+Devices")
struct EndpointsDevicesTests {

    @Test("registerDevice encodes platform as ios")
    func registerDevicePlatform() throws {
        let endpoint = try Endpoints.registerDevice(
            apnsToken: "abc",
            bundleId: "com.test",
            locale: "en_US",
            timeZone: "America/New_York"
        )
        let body = try JSONDecoder().decode(RegisterBody.self, from: endpoint.httpBody!)
        #expect(body.platform == "ios")
        #expect(body.apnsToken == "abc")
        #expect(body.bundleId == "com.test")
    }

    @Test("registerDevice uses POST to /book/me/devices/register")
    func registerDeviceMethod() throws {
        let endpoint = try Endpoints.registerDevice(
            apnsToken: "abc", bundleId: "com.test", locale: "en", timeZone: "UTC"
        )
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/me/devices/register")
        #expect(endpoint.requiresAuth)
    }

    @Test("unregisterDevice uses POST to /book/me/devices/unregister")
    func unregisterDeviceMethod() throws {
        let endpoint = try Endpoints.unregisterDevice(apnsToken: "deadbeef")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/me/devices/unregister")
        let body = try JSONDecoder().decode(UnregisterBody.self, from: endpoint.httpBody!)
        #expect(body.apnsToken == "deadbeef")
    }
}

private struct RegisterBody: Decodable {
    let platform: String
    let apnsToken: String
    let bundleId: String
    let locale: String
    let timeZone: String
}

private struct UnregisterBody: Decodable {
    let apnsToken: String
}
