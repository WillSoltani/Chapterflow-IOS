import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("Account persistence")
struct AccountPersistenceTests {
    @Test("same opaque namespace reopens ownerless pending rows")
    func sameNamespaceReopensPendingRows() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = "account-7f4c2b19"
        let loader = DefaultAccountPersistenceLoader(accountsRoot: root)

        do {
            let resources = try await loader.load(storageNamespace: namespace)
            let context = resources.controller.newBackgroundContext()
            context.insert(PendingAnnotationUpload(
                uploadId: "upload-a",
                annotationId: "annotation-a",
                requestJSON: "{}"
            ))
            try context.save()
        }

        let reopened = try await loader.load(storageNamespace: namespace)
        let context = reopened.controller.newBackgroundContext()

        #expect(try context.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 1)
        #expect(reopened.matches(storageNamespace: namespace))
        #expect(!reopened.matches(storageNamespace: "account-different"))
    }

    @Test("different opaque namespaces cannot observe each other's rows")
    func namespacesArePhysicallyIsolated() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = DefaultAccountPersistenceLoader(accountsRoot: root)

        let accountA = try await loader.load(storageNamespace: "account-a1")
        let contextA = accountA.controller.newBackgroundContext()
        contextA.insert(PendingAnnotationUpload(
            uploadId: "upload-a",
            annotationId: "annotation-a",
            requestJSON: "{}"
        ))
        try contextA.save()

        let accountB = try await loader.load(storageNamespace: "account-b2")
        let contextB = accountB.controller.newBackgroundContext()

        #expect(try contextA.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 1)
        #expect(try contextB.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 0)
        #expect(accountA.downloadFileStore.root != accountB.downloadFileStore.root)
    }

    @Test("legacy separate store remains untouched and invisible")
    func legacyStoreIsQuarantined() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacyURL = root.appending(path: "ChapterFlow.legacy.store")

        do {
            let legacy = try PersistenceController.makeDefault(storage: .privateStore(legacyURL))
            let context = legacy.newBackgroundContext()
            context.insert(PendingAnnotationUpload(
                uploadId: "legacy-upload",
                annotationId: "legacy-annotation",
                requestJSON: "{}"
            ))
            try context.save()
        }

        let loader = DefaultAccountPersistenceLoader(
            accountsRoot: root.appending(path: "accounts")
        )
        let account = try await loader.load(storageNamespace: "account-current")
        let accountContext = account.controller.newBackgroundContext()
        #expect(try accountContext.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 0)

        let reopenedLegacy = try PersistenceController.makeDefault(storage: .privateStore(legacyURL))
        let legacyContext = reopenedLegacy.newBackgroundContext()
        #expect(try legacyContext.fetchCount(FetchDescriptor<PendingAnnotationUpload>()) == 1)
    }

    @Test("account paths use only the opaque namespace")
    func pathsDoNotContainRawSubject() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawSubject = "raw-subject-person@example.com"
        let namespace = "account-84e13a09dbe2"
        let loader = DefaultAccountPersistenceLoader(accountsRoot: root)

        let resources = try await loader.load(storageNamespace: namespace)
        let namespaceRoot = resources.downloadFileStore.root.deletingLastPathComponent()
        let privateStoreURL = namespaceRoot.appending(path: "ChapterFlow.private.store")

        #expect(namespaceRoot.lastPathComponent == namespace)
        #expect(!namespaceRoot.path.contains(rawSubject))
        #expect(!privateStoreURL.path.contains(rawSubject))
        #expect(resources.downloadFileStore.root.lastPathComponent == "Downloads")
        #expect(FileManager.default.fileExists(atPath: privateStoreURL.path))
    }

    @Test("invalid namespace fails with a value-free category")
    func invalidNamespaceFailsClosed() async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = DefaultAccountPersistenceLoader(accountsRoot: root)

        do {
            _ = try await loader.load(storageNamespace: "raw/person@example.com")
            Issue.record("Unsafe namespace unexpectedly opened account storage")
        } catch let failure as AccountPersistenceLoadFailure {
            #expect(failure == .invalidStorageNamespace)
            #expect(
                String(reflecting: failure) ==
                    "Persistence.AccountPersistenceLoadFailure.invalidStorageNamespace"
            )
        } catch {
            Issue.record("Namespace failure escaped the closed error taxonomy")
        }
    }

    @Test("account loader leaves the shipping schema at V8")
    func currentSchemaIsUnchanged() {
        #expect(PersistenceMigrationPlan.currentVersion == PersistenceSchemaV8.versionIdentifier)
        #expect(PersistenceMigrationPlan.currentVersion == Schema.Version(8, 0, 0))
        #expect(PersistenceMigrationPlan.schemas.count == 8)
        #expect(PersistenceMigrationPlan.stages.count == 7)
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "cf-account-persistence-tests-\(UUID().uuidString)"
        )
    }
}

@Suite("Account-prefixed key-value storage")
struct AccountPrefixedKeyValueTests {
    private struct Sample: Codable, Equatable {
        let owner: String
    }

    @Test("KeyValueStore applies its prefix to every operation")
    func keyValuePrefixesIsolateAccounts() throws {
        let suite = "com.chapterflow.tests.account-kv.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = KeyValueStore(defaults: defaults, keyPrefix: "account-a.")
        let accountB = KeyValueStore(defaults: defaults, keyPrefix: "account-b.")

        try accountA.set(Sample(owner: "a"), forKey: "state")
        try accountB.set(Sample(owner: "b"), forKey: "state")

        #expect(accountA.value(Sample.self, forKey: "state") == Sample(owner: "a"))
        #expect(accountB.value(Sample.self, forKey: "state") == Sample(owner: "b"))
        #expect(defaults.object(forKey: "state") == nil)
        #expect(defaults.object(forKey: "account-a.state") != nil)
        #expect(defaults.object(forKey: "account-b.state") != nil)

        accountA.removeValue(forKey: "state")
        #expect(!accountA.contains("state"))
        #expect(accountB.contains("state"))
    }

    @MainActor
    @Test("AppPreferences applies its prefix to every preference key")
    func preferencePrefixesIsolateAccounts() {
        let suite = "com.chapterflow.tests.account-prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let accountA = AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        accountA.readingTone = .competitive
        accountA.depthVariant = .challenging
        accountA.themeMode = .dark
        accountA.readerTheme = .sepia
        accountA.readerFontScale = 1.4
        accountA.readerLineSpacing = 12
        accountA.audioSpeed = 1.5
        accountA.reminderHour = 7
        accountA.reminderMinute = 45
        accountA.interestIds = ["science"]
        accountA.onboardingCompleted = true
        accountA.downloadOverWifiOnly = true
        accountA.downloadStorageLimitGB = 9

        let accountB = AppPreferences(defaults: defaults, keyPrefix: "account-b.")
        #expect(accountB.readingTone == .direct)
        #expect(accountB.depthVariant == .medium)
        #expect(accountB.themeMode == .system)
        #expect(accountB.readerTheme == .system)
        #expect(accountB.readerFontScale == 1)
        #expect(accountB.readerLineSpacing == 6)
        #expect(accountB.audioSpeed == 1)
        #expect(accountB.reminderHour == 20)
        #expect(accountB.reminderMinute == 0)
        #expect(accountB.interestIds.isEmpty)
        #expect(!accountB.onboardingCompleted)
        #expect(!accountB.downloadOverWifiOnly)
        #expect(accountB.downloadStorageLimitGB == 5)

        let reopenedA = AppPreferences(defaults: defaults, keyPrefix: "account-a.")
        #expect(reopenedA.readingTone == .competitive)
        #expect(reopenedA.depthVariant == .challenging)
        #expect(reopenedA.themeMode == .dark)
        #expect(reopenedA.readerTheme == .sepia)
        #expect(reopenedA.readerFontScale == 1.4)
        #expect(reopenedA.readerLineSpacing == 12)
        #expect(reopenedA.audioSpeed == 1.5)
        #expect(reopenedA.reminderHour == 7)
        #expect(reopenedA.reminderMinute == 45)
        #expect(reopenedA.interestIds == ["science"])
        #expect(reopenedA.onboardingCompleted)
        #expect(reopenedA.downloadOverWifiOnly)
        #expect(reopenedA.downloadStorageLimitGB == 9)
        #expect(defaults.object(forKey: "pref.readingTone") == nil)
    }
}
