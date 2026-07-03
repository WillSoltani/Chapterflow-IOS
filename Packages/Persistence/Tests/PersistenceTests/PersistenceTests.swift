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

// MARK: - SwiftData container

@Suite("PersistenceController")
struct PersistenceControllerTests {
    @MainActor
    @Test("boots an in-memory container with the sample @Model and round-trips a record")
    func containerBoots() throws {
        let controller = try PersistenceController(
            models: PersistenceSchemaV2.models,
            storage: .inMemory,
            migrationPlan: PersistenceMigrationPlan.self
        )
        let context = controller.mainContext

        context.insert(CachedKeyValue(key: "greeting", value: "hello"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CachedKeyValue>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.value == "hello")
    }

    @Test("background store inserts and counts off the main actor")
    func backgroundStore() async throws {
        let controller = try PersistenceController(models: PersistenceSchemaV2.models, storage: .inMemory)
        let background = controller.backgroundStore()

        try await background.insert(CachedKeyValue(key: "k", value: "v"))
        let count = try await background.count(CachedKeyValue.self)
        #expect(count == 1)
    }

    @Test("LocalAnnotation round-trips in-memory")
    @MainActor
    func localAnnotationRoundTrip() throws {
        let controller = try PersistenceController(models: PersistenceSchemaV2.models, storage: .inMemory)
        let context = controller.mainContext

        let ann = LocalAnnotation(
            bookId: "book-1",
            chapterId: "ch-1",
            type: "highlight",
            colorRaw: "yellow",
            snippet: "Hello"
        )
        context.insert(ann)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LocalAnnotation>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.type == "highlight")
        #expect(fetched.first?.colorRaw == "yellow")
    }

    @Test("migration plan is well-formed with V1 → V2 → V3 → V4 stages")
    func migrationPlan() {
        #expect(PersistenceMigrationPlan.schemas.count == 4)
        #expect(PersistenceMigrationPlan.stages.count == 3)
        #expect(PersistenceSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(PersistenceSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(PersistenceSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(PersistenceSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    }

    @Test("PendingReviewGrade round-trips in-memory")
    @MainActor
    func pendingReviewGradeRoundTrip() throws {
        let controller = try PersistenceController(models: PersistenceSchemaV3.models, storage: .inMemory)
        let context = controller.mainContext

        let grade = PendingReviewGrade(
            cardId: "card-1",
            rating: 3,
            reviewedAt: "2026-01-01T00:00:00Z",
            optimisticStability: 5.0,
            optimisticDifficulty: 4.5,
            optimisticDueAt: "2026-01-04T00:00:00Z"
        )
        context.insert(grade)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PendingReviewGrade>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.cardId == "card-1")
        #expect(fetched.first?.rating == 3)
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
