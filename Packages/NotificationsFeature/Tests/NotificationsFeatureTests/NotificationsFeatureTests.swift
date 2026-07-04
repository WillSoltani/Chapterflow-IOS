import Testing
@testable import NotificationsFeature
import CoreKit
import Networking
import Foundation

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
    func registerRecordsToken() async {
        let repo = FakeDeviceRegistrationRepository()
        await repo.register(apnsToken: "abc123")
        #expect(repo.registeredTokens == ["abc123"])
    }

    @Test("unregister appends token to unregisteredTokens")
    func unregisterRecordsToken() async {
        let repo = FakeDeviceRegistrationRepository()
        await repo.unregister(apnsToken: "abc123")
        #expect(repo.unregisteredTokens == ["abc123"])
    }

    @Test("multiple registers accumulate all tokens")
    func multipleRegisters() async {
        let repo = FakeDeviceRegistrationRepository()
        await repo.register(apnsToken: "token1")
        await repo.register(apnsToken: "token2")
        #expect(repo.registeredTokens == ["token1", "token2"])
    }
}

// MARK: - APNSRegistrationManager de-duplication

@Suite("APNSRegistrationManager — de-dup")
@MainActor
struct APNSRegistrationManagerDedupTests {

    static let testDefaultsKey = "com.chapterflow.apnsLastRegisteredToken"

    func makeManager(
        defaults: UserDefaults = .standard,
        repo: FakeDeviceRegistrationRepository = .init()
    ) -> (APNSRegistrationManager, FakeDeviceRegistrationRepository) {
        let authorizer = MockNotificationAuthorizer()
        let manager = APNSRegistrationManager(
            authorizer: authorizer,
            repository: repo,
            defaults: defaults
        )
        return (manager, repo)
    }

    @Test("same token is not re-registered")
    func sameTokenSkipsRegistration() async {
        let defaults = UserDefaults(suiteName: "test-apns-dedup-same")!
        defaults.removeObject(forKey: "com.chapterflow.apnsLastRegisteredToken")
        let (manager, repo) = makeManager(defaults: defaults)

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
        defaults.removeObject(forKey: "com.chapterflow.apnsLastRegisteredToken")
        let (manager, repo) = makeManager(defaults: defaults)

        let token1 = Data([0x01, 0x02])
        let token2 = Data([0x03, 0x04])

        await manager.handleTokenReceived(token1)
        await manager.handleTokenReceived(token2)

        #expect(repo.registeredTokens.count == 2)
        #expect(repo.unregisteredTokens.count == 1)
        #expect(repo.unregisteredTokens.first == token1.apnsHex)
        defaults.removePersistentDomain(forName: "test-apns-dedup-rotate")
    }

    @Test("handleSignOut unregisters stored token and clears it")
    func signOutClearsToken() async {
        let defaults = UserDefaults(suiteName: "test-apns-signout")!
        defaults.set("stored_hex_token", forKey: "com.chapterflow.apnsLastRegisteredToken")
        let (manager, repo) = makeManager(defaults: defaults)

        await manager.handleSignOut()

        #expect(repo.unregisteredTokens == ["stored_hex_token"])
        #expect(defaults.string(forKey: "com.chapterflow.apnsLastRegisteredToken") == nil)
        defaults.removePersistentDomain(forName: "test-apns-signout")
    }

    @Test("handleSignOut is a no-op when no token is stored")
    func signOutWithNoStoredToken() async {
        let defaults = UserDefaults(suiteName: "test-apns-signout-empty")!
        defaults.removeObject(forKey: "com.chapterflow.apnsLastRegisteredToken")
        let (manager, repo) = makeManager(defaults: defaults)

        await manager.handleSignOut()

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
        defaults.removeObject(forKey: "com.chapterflow.apnsLastRegisteredToken")
        let (manager, _) = makeManager(defaults: defaults)

        manager.handleRegistrationFailed(URLError(.notConnectedToInternet))
        #expect(manager.registrationError != nil)

        await manager.handleTokenReceived(Data([0xAA, 0xBB]))
        #expect(manager.registrationError == nil)
        defaults.removePersistentDomain(forName: "test-apns-error-clear")
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
