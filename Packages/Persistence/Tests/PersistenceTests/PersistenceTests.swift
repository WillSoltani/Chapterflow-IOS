import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("Persistence")
struct PersistenceTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(Persistence.moduleName == "Persistence")
    }
}

// MARK: - Keychain / TokenStore

@Suite("TokenStore")
struct TokenStoreTests {
    /// Uses the in-memory fake - the real `TokenStore` calls `SecItem*` APIs that need
    /// a keychain-access-group entitlement unavailable in bare test bundles.
    private func makeStore() -> InMemoryTokenStore {
        InMemoryTokenStore()
    }

    // MARK: Keychain configuration (does NOT require Keychain entitlement)

    @Test("default configuration uses afterFirstUnlockThisDeviceOnly accessibility")
    func defaultConfigAccessibility() {
        let store = TokenStore()
        #expect(store.configuration.accessibility == .afterFirstUnlockThisDeviceOnly)
    }

    @Test("default configuration includes the App Group access group")
    func defaultConfigAppGroup() {
        let store = TokenStore()
        #expect(store.configuration.accessGroup == AppGroup.identifier)
    }

    @Test("afterFirstUnlockThisDeviceOnly maps to the correct CFString constant")
    func accessibilityConstant() {
        let accessibility = KeychainAccessibility.afterFirstUnlockThisDeviceOnly
        // Verify the raw Security framework constant. This catches accidental changes to
        // a weaker accessibility class (e.g. afterFirstUnlock, which allows iCloud sync).
        #expect(accessibility.secValue == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    private let sample = StoredTokens(
        idToken: "id-123",
        accessToken: "access-456",
        refreshToken: "refresh-789",
        expiresAt: Date.distantFuture
    )

    @Test("round-trips save → load → delete")
    func roundTrip() throws {
        let store = makeStore()

        // Empty to start.
        #expect(store.load() == nil)

        // Save then load returns the same triple.
        try store.save(sample)
        #expect(store.load() == sample)

        // Delete removes everything.
        try store.delete()
        #expect(store.load() == nil)
    }

    @Test("load returns nil on a fresh store")
    func freshStoreReturnsNil() {
        let store = makeStore()
        #expect(store.load() == nil)
    }

    @Test("overwrites an existing token")
    func overwrite() throws {
        let store = makeStore()
        try store.save(sample)

        let updated = StoredTokens(
            idToken: "id-new",
            accessToken: "acc-new",
            refreshToken: "ref-new",
            expiresAt: Date.distantFuture
        )
        try store.save(updated)

        #expect(store.load() == updated)
        try store.delete()
    }

    @Test("isExpired and isNearlyExpired reflect expiresAt")
    func expiry() {
        let expired = StoredTokens(
            idToken: "t", accessToken: "t", refreshToken: "t",
            expiresAt: Date.distantPast
        )
        #expect(expired.isExpired())
        #expect(expired.isNearlyExpired())

        let fresh = StoredTokens(
            idToken: "t", accessToken: "t", refreshToken: "t",
            expiresAt: Date.distantFuture
        )
        #expect(!fresh.isExpired())
        #expect(!fresh.isNearlyExpired())
    }
}

// MARK: - SwiftData migration plan (no container creation)

@Suite("PersistenceSchema")
struct PersistenceSchemaTests {
    @Test("migration plan is well-formed with V1 → V2 → V3 → V4 → V5 → V6 → V7 stages")
    func migrationPlan() {
        #expect(PersistenceMigrationPlan.schemas.count == 7)
        #expect(PersistenceMigrationPlan.stages.count == 6)
        #expect(PersistenceSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(PersistenceSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(PersistenceSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(PersistenceSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(PersistenceSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(PersistenceSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(PersistenceSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
    }
}

// MARK: - AppPreferences

@Suite("AppPreferences")
struct AppPreferencesTests {
    /// A throwaway UserDefaults suite that is cleaned up after use.
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "com.chapterflow.tests.prefs.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @MainActor
    @Test("provides sensible defaults")
    func defaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.readingTone == .direct)
        #expect(prefs.depthVariant == .medium)
        #expect(prefs.themeMode == .system)
        #expect(prefs.readerFontScale == 1.0)
        #expect(prefs.audioSpeed == 1.0)
        #expect(prefs.reminderHour == 20)
        #expect(prefs.reminderMinute == 0)
        #expect(prefs.interestIds.isEmpty)
        #expect(prefs.onboardingCompleted == false)
    }

    @MainActor
    @Test("interestIds persists across instances")
    func interestIdsPersists() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppPreferences(defaults: defaults)
        first.interestIds = ["business", "science"]
        let second = AppPreferences(defaults: defaults)
        #expect(second.interestIds == ["business", "science"])
    }

    @MainActor
    @Test("onboardingCompleted persists across instances")
    func onboardingCompletedPersists() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppPreferences(defaults: defaults)
        #expect(first.onboardingCompleted == false)
        first.onboardingCompleted = true
        let second = AppPreferences(defaults: defaults)
        #expect(second.onboardingCompleted == true)
    }

    @MainActor
    @Test("persists changes across instances")
    func persistsAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppPreferences(defaults: defaults)
        first.readingTone = .competitive
        first.depthVariant = .challenging
        first.themeMode = .dark
        first.readerFontScale = 1.35
        first.audioSpeed = 1.5
        first.reminderTime = DateComponents(hour: 7, minute: 30)

        // A brand-new instance over the same defaults sees the persisted values.
        let second = AppPreferences(defaults: defaults)
        #expect(second.readingTone == .competitive)
        #expect(second.depthVariant == .challenging)
        #expect(second.themeMode == .dark)
        #expect(second.readerFontScale == 1.35)
        #expect(second.audioSpeed == 1.5)
        #expect(second.reminderHour == 7)
        #expect(second.reminderMinute == 30)
    }
}

// MARK: - KeyValueStore

@Suite("KeyValueStore")
struct KeyValueStoreTests {
    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
    }

    private func makeStore() -> (store: KeyValueStore, suite: String) {
        let suite = "com.chapterflow.tests.kv.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (KeyValueStore(defaults: defaults), suite)
    }

    @Test("round-trips a Codable value")
    func roundTrip() throws {
        let (store, suite) = makeStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        #expect(store.value(Sample.self, forKey: "s") == nil)
        #expect(store.contains("s") == false)

        let value = Sample(name: "chapter", count: 3)
        try store.set(value, forKey: "s")

        #expect(store.contains("s"))
        #expect(store.value(Sample.self, forKey: "s") == value)

        store.removeValue(forKey: "s")
        #expect(store.value(Sample.self, forKey: "s") == nil)
    }
}

// MARK: - FileStore

@Suite("FileStore")
struct FileStoreTests {
    @Test("round-trips a blob and excludes the root from backup")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cf-tests-\(UUID().uuidString)")
        let store = try FileStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data("audio-bytes".utf8)
        #expect(store.exists("clip.mp3") == false)

        try store.write(payload, named: "clip.mp3")
        #expect(store.exists("clip.mp3"))
        #expect(try store.read(named: "clip.mp3") == payload)

        // Root is excluded from iCloud backup.
        let values = try store.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)

        try store.remove(named: "clip.mp3")
        #expect(store.exists("clip.mp3") == false)
    }

    @Test("reading a missing file throws notFound")
    func missingThrows() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cf-tests-\(UUID().uuidString)")
        let store = try FileStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: PersistenceError.notFound) {
            try store.read(named: "nope.dat")
        }
    }
}

// MARK: - DailyGoalStore

@Suite("DailyGoalStore")
struct DailyGoalStoreTests {

    private func freshStore() -> (DailyGoalStore, String) {
        let suite = "com.chapterflow.tests.goal.\(UUID().uuidString)"
        return (DailyGoalStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    @Test("defaults to 10 minutes on a fresh store")
    func defaultGoal() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(store.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(store.dailyGoalMinutes == 10)
    }

    @Test("persists a valid tier value across instances")
    func persistsAcrossInstances() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        store.dailyGoalMinutes = 20
        let store2 = DailyGoalStore(defaults: defaults)
        #expect(store2.dailyGoalMinutes == 20)
    }

    @Test("snaps values below range to 10")
    func snapsLow() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        store.dailyGoalMinutes = 0
        #expect(store.dailyGoalMinutes == 10)
    }

    @Test("snaps values above range to 30")
    func snapsHigh() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        store.dailyGoalMinutes = 999
        #expect(store.dailyGoalMinutes == 30)
    }

    @Test("tiers are exactly [10, 20, 30]")
    func tierValues() {
        #expect(DailyGoalStore.tiers == [10, 20, 30])
    }

    @Test("options equals tiers")
    func optionsEqualsTiers() {
        #expect(DailyGoalStore.options == DailyGoalStore.tiers)
    }

    @Test("progressFraction caps at 1.0 when over goal")
    func progressFractionCapped() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        store.dailyGoalMinutes = 10
        #expect(store.progressFraction(todayMinutes: 30) == 1.0)
    }

    @Test("progressFraction is accurate at partial progress")
    func progressFractionPartial() {
        let (store, suite) = freshStore()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        store.dailyGoalMinutes = 20
        #expect(abs(store.progressFraction(todayMinutes: 10) - 0.5) < 0.001)
    }
}
