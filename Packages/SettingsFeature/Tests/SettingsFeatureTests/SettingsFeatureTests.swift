import Testing
import Foundation
@testable import SettingsFeature
import AuthKit
import CoreKit
import Persistence
import Networking

private func makeSettingsAccountContext(
    accountID: String = "settings-test-account"
) throws -> AccountContext {
    let identity = try #require(SessionIdentity(
        subject: accountID,
        username: "settings-test-reader",
        email: "settings-reader@example.test",
        source: .hermeticUITest
    ))
    let config = AppConfig(
        apiBaseURL: "https://api.chapterflow.test",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_ChapterFlowTests",
        cognitoClientID: "ChapterFlowSettingsTests1234567890",
        cognitoDomain: "chapterflow-tests.auth.us-east-1.amazoncognito.com"
    )
    guard case let .valid(validatedConfig) = config.validate() else {
        Issue.record("Expected the static SettingsFeature test configuration to be valid")
        throw SettingsTestSetupError.invalidConfiguration
    }
    return AccountContext(identity: identity, config: validatedConfig)
}

private enum SettingsTestSetupError: Error {
    case invalidConfiguration
}

// MARK: - Module smoke test

@Suite("SettingsFeature")
struct SettingsFeatureTests {

    @Test("module exposes its name")
    func moduleName() {
        #expect(SettingsFeature.moduleName == "SettingsFeature")
    }

    // MARK: - SettingsView init (backwards-compat)

    @Test("SettingsView initializes with default free state")
    @MainActor
    func settingsViewDefaultInit() {
        let view = SettingsView()
        _ = view
    }

    @Test("SettingsView initializes with Pro state")
    @MainActor
    func settingsViewProInit() {
        let periodEnd = Date(timeIntervalSinceNow: 30 * 24 * 3600)
        let view = SettingsView(
            isPro: true,
            currentPeriodEnd: periodEnd,
            cancelAtPeriodEnd: false
        )
        _ = view
    }

    @Test("SettingsView initializes with free state and remaining starts")
    @MainActor
    func settingsViewFreeWithStartsInit() {
        let view = SettingsView(isPro: false, remainingFreeStarts: 3)
        _ = view
    }

    @Test("SettingsView callbacks can be provided and are callable")
    @MainActor
    func settingsViewCallbacksAreCallable() {
        var paywallCalled = false
        var manageCalled = false
        let onShowPaywall: () -> Void = { paywallCalled = true }
        let onManage: () -> Void = { manageCalled = true }

        let view = SettingsView(
            isPro: false,
            onShowPaywall: onShowPaywall,
            onManageSubscription: onManage
        )
        _ = view

        // Verify closures capture state correctly.
        onShowPaywall()
        onManage()
        #expect(paywallCalled)
        #expect(manageCalled)
    }
}

// MARK: - FakeSettingsRepository

@Suite("FakeSettingsRepository")
struct FakeSettingsRepositoryTests {

    @Test("returns stubbed settings")
    func returnsStubbedSettings() async throws {
        let repo = FakeSettingsRepository(
            settings: UserReadingSettings(
                defaultDepth: "hard",
                readingTone: "competitive",
                fontScale: 1.2,
                audioSpeed: 1.5
            )
        )
        let settings = try await repo.getReadingSettings()
        #expect(settings?.defaultDepth == "hard")
        #expect(settings?.readingTone == "competitive")
        #expect(settings?.fontScale == 1.2)
        #expect(settings?.audioSpeed == 1.5)
    }

    @Test("records patched settings")
    func recordsPatchedSettings() async throws {
        let repo = FakeSettingsRepository()
        let patch = UserReadingSettings(
            defaultDepth: "easy",
            readingTone: "gentle",
            fontScale: 0.9,
            audioSpeed: 1.0
        )
        try await repo.patchReadingSettings(patch)
        #expect(repo.patchedSettings?.defaultDepth == "easy")
        #expect(repo.patchedSettings?.readingTone == "gentle")
    }

    @Test("returns stubbed export data")
    func returnsStubbedExportData() async throws {
        let expectedData = Data("export content".utf8)
        let repo = FakeSettingsRepository(exportData: expectedData)
        let data = try await repo.exportData()
        #expect(data == expectedData)
    }

    @Test("records deactivate call")
    func recordsDeactivateCall() async throws {
        let repo = FakeSettingsRepository()
        try await repo.deactivateAccount()
        #expect(repo.deactivateCalled)
    }

    @Test("records delete call")
    func recordsDeleteCall() async throws {
        let repo = FakeSettingsRepository()
        try await repo.deleteAccount()
        #expect(repo.deleteCalled)
    }

    @Test("throws when shouldFail is true")
    func throwsWhenShouldFail() async {
        let repo = FakeSettingsRepository(shouldFail: true)
        await #expect(throws: (any Error).self) {
            try await repo.getReadingSettings()
        }
        await #expect(throws: (any Error).self) {
            let patch = UserReadingSettings()
            try await repo.patchReadingSettings(patch)
        }
        await #expect(throws: (any Error).self) {
            try await repo.exportData()
        }
        await #expect(throws: (any Error).self) {
            try await repo.deactivateAccount()
        }
        await #expect(throws: (any Error).self) {
            try await repo.deleteAccount()
        }
    }
}

// MARK: - SettingsModel

@Suite("SettingsModel")
struct SettingsModelTests {

    @Test("model retains the exact proven account context")
    @MainActor
    func modelRetainsExactAccountContext() throws {
        let context = try makeSettingsAccountContext(accountID: "settings-account-a")
        let model = SettingsModel(
            repository: FakeSettingsRepository(),
            preferences: AppPreferences(defaults: UserDefaults(suiteName: "test.settings.context")),
            onSignOut: {},
            accountContext: context
        )

        #expect(model.accountContext == context)
        #expect(model.accountContext.accountID == "settings-account-a")
    }

    @Test(
        "fallback identities cannot reach the SettingsModel constructor",
        arguments: ["", " ", " account-with-padding ", "anon", "ANON", "local", "LOCAL"]
    )
    func fallbackIdentitiesAreRejected(_ accountID: String) {
        #expect(SessionIdentity(
            subject: accountID,
            username: "settings-reader",
            email: nil,
            source: .cognitoUserPool
        ) == nil)
    }

    @Test("load syncs remote depth into AppPreferences")
    @MainActor
    func loadSyncsDepth() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.depth"))
        let repo = FakeSettingsRepository(
            settings: UserReadingSettings(defaultDepth: "hard", readingTone: "competitive")
        )
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.load()
        #expect(prefs.depthVariant == .hard)
        #expect(prefs.readingTone == .competitive)
    }

    @Test("load ignores unknown depth values gracefully")
    @MainActor
    func loadIgnoresUnknownDepth() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.unknown"))
        prefs.depthVariant = .medium
        let repo = FakeSettingsRepository(
            settings: UserReadingSettings(defaultDepth: "unknown_depth_xyz")
        )
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.load()
        // Unknown value must not crash; local pref unchanged.
        #expect(prefs.depthVariant == .medium)
    }

    @Test("load clamps fontScale to valid range")
    @MainActor
    func loadClampsFontScale() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.clamp"))
        let repo = FakeSettingsRepository(
            settings: UserReadingSettings(fontScale: 5.0) // out of range
        )
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.load()
        #expect(prefs.readerFontScale <= 1.8)
    }

    @Test("load is non-fatal when repository throws")
    @MainActor
    func loadIsNonFatalOnError() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.nonfatal"))
        prefs.depthVariant = .easy
        let repo = FakeSettingsRepository(shouldFail: true)
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.load()
        // Should not throw; local prefs unchanged.
        #expect(prefs.depthVariant == .easy)
        #expect(model.error == nil)
    }

    @Test("requestExport populates exportData on success")
    @MainActor
    func requestExportPopulatesData() async throws {
        let expectedData = Data("my data".utf8)
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.export"))
        let repo = FakeSettingsRepository(exportData: expectedData)
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.requestExport()
        #expect(model.exportData == expectedData)
        #expect(model.showShareSheet)
    }

    @Test("requestExport sets error on failure")
    @MainActor
    func requestExportSetsErrorOnFailure() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.exportfail"))
        let repo = FakeSettingsRepository(shouldFail: true)
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )
        await model.requestExport()
        #expect(model.exportData == nil)
        #expect(model.error != nil)
    }

    @Test("confirmDelete calls repository and signs out")
    @MainActor
    func confirmDeleteCallsRepoAndSignsOut() async throws {
        let repo = FakeSettingsRepository()
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.delete"))
        var signedOut = false
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: { signedOut = true },
            accountContext: try makeSettingsAccountContext()
        )
        await model.confirmDelete()
        #expect(repo.deleteCalled)
        #expect(signedOut)
    }

    @Test("confirmDeactivate calls repository and signs out")
    @MainActor
    func confirmDeactivateCallsRepoAndSignsOut() async throws {
        let repo = FakeSettingsRepository()
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.deactivate"))
        var signedOut = false
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: { signedOut = true },
            accountContext: try makeSettingsAccountContext()
        )
        await model.confirmDeactivate()
        #expect(repo.deactivateCalled)
        #expect(signedOut)
    }

    @Test("confirmDelete sets error and does not sign out on failure")
    @MainActor
    func confirmDeleteSetsErrorOnFailure() async throws {
        let repo = FakeSettingsRepository(shouldFail: true)
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.deletefail"))
        var signedOut = false
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: { signedOut = true },
            accountContext: try makeSettingsAccountContext()
        )
        await model.confirmDelete()
        #expect(model.error != nil)
        #expect(!signedOut)
    }

    @Test("missing account-scoped download provider stays empty without legacy fallback")
    @MainActor
    func missingDownloadProviderFailsClosed() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "test.settings.dlall"))
        let repo = FakeSettingsRepository()
        let model = SettingsModel(
            repository: repo,
            preferences: prefs,
            onSignOut: {},
            accountContext: try makeSettingsAccountContext()
        )

        await model.load()
        model.deleteAllDownloads()
        #expect(model.downloadedFiles.isEmpty)
        #expect(model.totalDownloadBytes == 0)
    }
}

// MARK: - UserReadingSettings

@Suite("UserReadingSettings")
struct UserReadingSettingsTests {

    @Test("equatable comparison")
    func equatableComparison() {
        let a = UserReadingSettings(defaultDepth: "medium", readingTone: "direct")
        let b = UserReadingSettings(defaultDepth: "medium", readingTone: "direct")
        let c = UserReadingSettings(defaultDepth: "hard", readingTone: "direct")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("nil fields are tolerated")
    func nilFieldsAreTolerated() {
        let s = UserReadingSettings()
        #expect(s.defaultDepth == nil)
        #expect(s.readingTone == nil)
        #expect(s.fontScale == nil)
        #expect(s.audioSpeed == nil)
    }
}

// MARK: - MockAPIClient sendData

@Suite("MockAPIClient.sendData")
struct MockAPIClientSendDataTests {

    @Test("returns stubbed data for path")
    func returnsStubbedData() async throws {
        let mock = MockAPIClient()
        let expected = Data("export".utf8)
        await mock.setStub(.success(expected), for: "/book/me/export")
        let result = try await mock.sendData(Endpoints.getExport())
        #expect(result == expected)
    }

    @Test("throws stubbed error for path")
    func throwsStubbedError() async {
        let mock = MockAPIClient()
        await mock.setStub(.failure(.offline), for: "/book/me/export")
        await #expect(throws: (any Error).self) {
            try await mock.sendData(Endpoints.getExport())
        }
    }

    @Test("records endpoint for sendData call")
    func recordsEndpoint() async throws {
        let mock = MockAPIClient()
        let endpoint = Endpoints.getExport()
        _ = try? await mock.sendData(endpoint)
        let recorded = await mock.recordedEndpoints
        #expect(recorded.contains(endpoint))
    }
}
