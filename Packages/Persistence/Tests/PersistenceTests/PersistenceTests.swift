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
    /// A store backed by the in-memory Keychain fake. The real `SystemKeychain` path is
    /// exercised by the app at runtime (it needs the app's keychain-access-group
    /// entitlement, which a bare test bundle lacks — hence `errSecMissingEntitlement`).
    private func makeStore() -> TokenStore {
        TokenStore(keychain: InMemoryKeychain())
    }

    private let sample = TokenStore.Tokens(
        idToken: "id-123",
        accessToken: "access-456",
        refreshToken: "refresh-789"
    )

    @Test("round-trips set → get → clear")
    func roundTrip() async throws {
        let store = makeStore()

        // Empty to start.
        #expect(try await store.load() == nil)

        // Save then load returns the same triple.
        try await store.save(sample)
        let loaded = try await store.load()
        #expect(loaded == sample)

        // Clear removes everything.
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("load returns nil when the triple is incomplete")
    func partialLoad() async throws {
        // Only the id token present → load yields nil (all three are required).
        let keychain = InMemoryKeychain()
        try keychain.set(Data("only-id".utf8), for: "cognito.idToken")
        let store = TokenStore(keychain: keychain)
        #expect(try await store.load() == nil)
    }

    @Test("overwrites an existing token")
    func overwrite() async throws {
        let store = makeStore()
        try await store.save(sample)

        let updated = TokenStore.Tokens(idToken: "id-new", accessToken: "acc-new", refreshToken: "ref-new")
        try await store.save(updated)

        #expect(try await store.load() == updated)
        try await store.clear()
    }

    @Test("changes stream emits on save and clear")
    func changesStream() async throws {
        let store = makeStore()
        var iterator = await store.changes().makeAsyncIterator()

        try await store.save(sample)
        let first = await iterator.next()
        #expect(first ?? nil == sample)

        try await store.clear()
        let second = await iterator.next()
        // Cleared → yields `Optional<Tokens>.some(nil)`.
        #expect(second == .some(nil))
    }
}

// MARK: - SwiftData container

@Suite("PersistenceController")
struct PersistenceControllerTests {
    @MainActor
    @Test("boots an in-memory container with the sample @Model and round-trips a record")
    func containerBoots() throws {
        let controller = try PersistenceController(
            models: PersistenceSchemaV1.models,
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
        let controller = try PersistenceController(models: PersistenceSchemaV1.models, storage: .inMemory)
        let background = controller.backgroundStore()

        try await background.insert(CachedKeyValue(key: "k", value: "v"))
        let count = try await background.count(CachedKeyValue.self)
        #expect(count == 1)
    }

    @Test("migration plan scaffold is well-formed")
    func migrationPlan() {
        #expect(PersistenceMigrationPlan.schemas.count == 1)
        #expect(PersistenceMigrationPlan.stages.isEmpty)
        #expect(PersistenceSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
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

    private func makeStore() -> (KeyValueStore, UserDefaults, String) {
        let suite = "com.chapterflow.tests.kv.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (KeyValueStore(defaults: defaults), defaults, suite)
    }

    @Test("round-trips a Codable value")
    func roundTrip() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

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
