import Testing
import Foundation
import Models
import CoreKit
import Networking
@testable import SocialFeature

// MARK: - ChapterReflection model tests

@Suite("ChapterReflection")
struct ChapterReflectionTests {

    @Test("decodes from canonical JSON")
    func decodesFromJSON() throws {
        let json = """
        {
          "reflectionId": "r-abc",
          "bookId": "atomic-habits",
          "chapterN": 3,
          "text": "The habit loop concept really landed for me.",
          "createdAt": "2024-06-01T10:00:00Z"
        }
        """.data(using: .utf8)!

        let reflection = try JSONDecoder.chapterFlow.decode(ChapterReflection.self, from: json)
        #expect(reflection.reflectionId == "r-abc")
        #expect(reflection.bookId == "atomic-habits")
        #expect(reflection.chapterN == 3)
        #expect(reflection.text == "The habit loop concept really landed for me.")
        #expect(reflection.feedbackText == nil)
    }

    @Test("decodes feedbackText when present")
    func decodesFeedbackText() throws {
        let json = """
        {
          "reflectionId": "r-xyz",
          "bookId": "deep-work",
          "chapterN": 1,
          "text": "Deep focus is rare.",
          "createdAt": "2024-06-01T10:00:00Z",
          "feedbackText": "Excellent insight — scarcity creates value."
        }
        """.data(using: .utf8)!

        let reflection = try JSONDecoder.chapterFlow.decode(ChapterReflection.self, from: json)
        #expect(reflection.feedbackText == "Excellent insight — scarcity creates value.")
    }

    @Test("ReflectionsResponse decodes array lossily")
    func reflectionsResponseLossyArray() throws {
        let json = """
        {
          "reflections": [
            {
              "reflectionId": "r1",
              "bookId": "bk",
              "chapterN": 1,
              "text": "Valid",
              "createdAt": "2024-01-01T00:00:00Z"
            },
            null,
            {
              "reflectionId": "r2",
              "bookId": "bk",
              "chapterN": 1,
              "text": "Also valid",
              "createdAt": "2024-01-02T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.chapterFlow.decode(ReflectionsResponse.self, from: json)
        #expect(response.reflections.count == 2)
        #expect(response.reflections[0].reflectionId == "r1")
        #expect(response.reflections[1].reflectionId == "r2")
    }

    @Test("ReflectionFeedbackResponse decodes feedbackText")
    func feedbackResponseDecodes() throws {
        let json = """
        { "feedbackText": "Great reflection on the core idea!" }
        """.data(using: .utf8)!

        let response = try JSONDecoder.chapterFlow.decode(ReflectionFeedbackResponse.self, from: json)
        #expect(response.feedbackText == "Great reflection on the core idea!")
    }
}

// MARK: - PendingReflectionItem tests

@Suite("PendingReflectionItem")
struct PendingReflectionItemTests {

    @Test("defaults to syncState pending")
    func defaultsSyncStatePending() {
        let item = PendingReflectionItem(bookId: "bk", chapterN: 1, text: "Hello")
        #expect(item.syncState == .pending)
        #expect(item.serverReflectionId == nil)
        #expect(item.feedbackState == .none)
        #expect(item.feedbackText == nil)
    }

    @Test("round-trips through JSON encoding")
    func jsonRoundTrip() throws {
        let original = PendingReflectionItem(
            localId: "local-42",
            bookId: "deep-work",
            chapterN: 5,
            text: "Focus is everything.",
            syncState: .synced,
            serverReflectionId: "server-99",
            feedbackState: .received,
            feedbackText: "Well observed!"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingReflectionItem.self, from: data)

        #expect(decoded.localId == "local-42")
        #expect(decoded.bookId == "deep-work")
        #expect(decoded.chapterN == 5)
        #expect(decoded.syncState == .synced)
        #expect(decoded.serverReflectionId == "server-99")
        #expect(decoded.feedbackState == .received)
        #expect(decoded.feedbackText == "Well observed!")
    }
}

// MARK: - FakeSocialRepository reflection tests

@Suite("FakeSocialRepository — reflections")
struct FakeSocialRepositoryReflectionTests {

    @Test("getReflections returns empty list for unset book/chapter")
    func getReflectionsEmpty() async throws {
        let repo = FakeSocialRepository()
        let reflections = try await repo.getReflections(bookId: "bk", chapterN: 1)
        #expect(reflections.isEmpty)
    }

    @Test("getReflections returns seeded reflections")
    func getReflectionsSeeded() async throws {
        let refl = ChapterReflection(
            reflectionId: "r1", bookId: "bk", chapterN: 2,
            text: "Hello world", createdAt: Date()
        )
        let repo = FakeSocialRepository(
            serverReflections: ["bk": ["2": [refl]]]
        )
        let fetched = try await repo.getReflections(bookId: "bk", chapterN: 2)
        #expect(fetched.count == 1)
        #expect(fetched[0].reflectionId == "r1")
    }

    @Test("postReflection auto-syncs in fake and appends to server list")
    func postReflectionAutoSyncs() async throws {
        let repo = FakeSocialRepository()
        let item = try await repo.postReflection(bookId: "bk", chapterN: 1, text: "My thought")
        #expect(item.syncState == .synced)
        #expect(item.serverReflectionId != nil)

        let serverList = try? await repo.getReflections(bookId: "bk", chapterN: 1)
        #expect(serverList?.count == 1)
        #expect(serverList?.first?.text == "My thought")
    }

    @Test("getPendingReflections returns only items for matching book/chapter")
    func getPendingFiltersCorrectly() async throws {
        let repo = FakeSocialRepository()
        _ = try await repo.postReflection(bookId: "bk", chapterN: 1, text: "Chapter 1 thought")
        _ = try await repo.postReflection(bookId: "bk", chapterN: 2, text: "Chapter 2 thought")

        let ch1Pending = await repo.getPendingReflections(bookId: "bk", chapterN: 1)
        let ch2Pending = await repo.getPendingReflections(bookId: "bk", chapterN: 2)
        #expect(ch1Pending.count == 1)
        #expect(ch2Pending.count == 1)
        #expect(ch1Pending[0].text == "Chapter 1 thought")
        #expect(ch2Pending[0].text == "Chapter 2 thought")
    }

    @Test("requestFeedback returns AI feedback text")
    func requestFeedbackReturnsText() async throws {
        let repo = FakeSocialRepository()
        let text = try await repo.requestFeedback(
            bookId: "bk", chapterN: 1, serverReflectionId: "r-any"
        )
        #expect(!text.isEmpty)
    }

    @Test("requestFeedback propagates forced error")
    func requestFeedbackForcedError() async {
        let repo = FakeSocialRepository(error: .offline)
        var caught = false
        do {
            _ = try await repo.requestFeedback(
                bookId: "bk", chapterN: 1, serverReflectionId: "r-any"
            )
        } catch let e as AppError {
            if case .offline = e { caught = true }
        } catch {}
        #expect(caught)
    }

    @Test("queueFeedbackForPending marks item feedbackState as pending")
    func queueFeedbackMarksPending() async throws {
        let repo = FakeSocialRepository()
        let posted = try await repo.postReflection(bookId: "bk", chapterN: 1, text: "Insight")
        let updated = try await repo.queueFeedbackForPending(localId: posted.localId)
        #expect(updated?.feedbackState == .pending)
    }

    @Test("syncPendingReflections returns current pending list")
    func syncPendingReflectionsReturns() async throws {
        let repo = FakeSocialRepository()
        _ = try await repo.postReflection(bookId: "bk", chapterN: 3, text: "To sync")
        let result = try await repo.syncPendingReflections(bookId: "bk", chapterN: 3)
        #expect(!result.isEmpty)
    }
}

// MARK: - ReflectionOutbox tests

@Suite("ReflectionOutbox")
struct ReflectionOutboxTests {

    private let accountA = "account-v1-" + String(repeating: "a", count: 64)
    private let accountB = "account-v1-" + String(repeating: "b", count: 64)

    // Each test gets its own temp file so tests are hermetic and don't touch real app storage.
    private func makeOutbox() -> (outbox: ReflectionOutbox, permit: SessionWorkPermit) {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "test_outbox_\(UUID().uuidString).json")
        let permit = SessionWorkPermit()
        return (ReflectionOutbox(fileURL: tmpFile, workPermit: permit), permit)
    }

    @Test("append and query by bookId/chapterN")
    func appendAndQuery() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        let id = UUID().uuidString
        let item = PendingReflectionItem(localId: id, bookId: "bk", chapterN: 4, text: "Test")
        try await outbox.append(item, ticket: ticket)

        let fetched = await outbox.all(bookId: "bk", chapterN: 4)
        let match = fetched.first { $0.localId == id }
        #expect(match != nil)
        #expect(match?.text == "Test")
    }

    @Test("update replaces item with matching localId")
    func updateReplacesItem() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        var item = PendingReflectionItem(localId: "u-1", bookId: "bk", chapterN: 4, text: "Initial")
        try await outbox.append(item, ticket: ticket)

        item.syncState = .synced
        item.serverReflectionId = "server-1"
        try await outbox.update(item, ticket: ticket)

        let fetched = await outbox.all(bookId: "bk", chapterN: 4)
        let match = fetched.first { $0.localId == "u-1" }
        #expect(match?.syncState == .synced)
        #expect(match?.serverReflectionId == "server-1")
    }

    @Test("markFeedbackPending sets feedbackState")
    func markFeedbackPendingSetsState() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        let item = PendingReflectionItem(localId: "fb-1", bookId: "bk", chapterN: 4, text: "Hi")
        try await outbox.append(item, ticket: ticket)
        try await outbox.markFeedbackPending(localId: "fb-1", ticket: ticket)

        let fetched = await outbox.all(bookId: "bk", chapterN: 4)
        let match = fetched.first { $0.localId == "fb-1" }
        #expect(match?.feedbackState == .pending)
    }

    @Test("markFeedbackReceived stores feedback text")
    func markFeedbackReceivedStoresText() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        let item = PendingReflectionItem(localId: "fb-2", bookId: "bk", chapterN: 4, text: "Hi")
        try await outbox.append(item, ticket: ticket)
        try await outbox.markFeedbackReceived(
            localId: "fb-2",
            feedbackText: "Great work!",
            ticket: ticket
        )

        let fetched = await outbox.all(bookId: "bk", chapterN: 4)
        let match = fetched.first { $0.localId == "fb-2" }
        #expect(match?.feedbackState == .received)
        #expect(match?.feedbackText == "Great work!")
    }

    @Test("remove deletes item with matching localId")
    func removeDeletesItem() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        let item = PendingReflectionItem(localId: "del-1", bookId: "bk", chapterN: 4, text: "Gone")
        try await outbox.append(item, ticket: ticket)
        try await outbox.remove(localId: "del-1", ticket: ticket)

        let fetched = await outbox.all(bookId: "bk", chapterN: 4)
        #expect(fetched.allSatisfy { $0.localId != "del-1" })
    }

    @Test("all filters by bookId and chapterN")
    func allFiltersByBookAndChapter() async throws {
        let (outbox, permit) = makeOutbox()
        let ticket = try permit.begin()
        try await outbox.append(
            PendingReflectionItem(localId: "a1", bookId: "bk1", chapterN: 1, text: "A"),
            ticket: ticket
        )
        try await outbox.append(
            PendingReflectionItem(localId: "a2", bookId: "bk1", chapterN: 2, text: "B"),
            ticket: ticket
        )
        try await outbox.append(
            PendingReflectionItem(localId: "a3", bookId: "bk2", chapterN: 1, text: "C"),
            ticket: ticket
        )

        let ch1 = await outbox.all(bookId: "bk1", chapterN: 1)
        let ch2 = await outbox.all(bookId: "bk1", chapterN: 2)
        let bk2 = await outbox.all(bookId: "bk2", chapterN: 1)

        #expect(ch1.contains { $0.localId == "a1" })
        #expect(!ch1.contains { $0.localId == "a2" })
        #expect(ch2.contains { $0.localId == "a2" })
        #expect(bk2.contains { $0.localId == "a3" })
    }

    @Test("account B cannot read or drain account A pending reflections")
    func accountOutboxesAreIsolated() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appending(path: "ReflectionAccountIsolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let permitA = SessionWorkPermit()
        let outboxA = try ReflectionOutbox(
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport,
            workPermit: permitA
        )
        let outboxB = try ReflectionOutbox(
            storageNamespace: accountB,
            applicationSupportDirectory: applicationSupport
        )
        let pending = PendingReflectionItem(
            localId: "owned-by-a",
            bookId: "book-a",
            chapterN: 1,
            text: "Synthetic account A reflection",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try await outboxA.append(pending, ticket: permitA.begin())

        #expect(await outboxB.all(bookId: "book-a", chapterN: 1).isEmpty)
        let relaunchedA = try ReflectionOutbox(
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )
        #expect(await relaunchedA.all(bookId: "book-a", chapterN: 1) == [pending])
    }

    @Test("legacy unknown-owner outbox remains untouched and unattributed")
    func legacyOutboxIsPreserved() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appending(path: "ReflectionLegacyPreservation-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport
            .appending(path: "ChapterFlow", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appending(path: "pending_reflections.json")
        let legacyData = Data("legacy-unknown-owner".utf8)
        try legacyData.write(to: legacyURL)

        let outboxA = try ReflectionOutbox(
            storageNamespace: accountA,
            applicationSupportDirectory: applicationSupport
        )
        let outboxB = try ReflectionOutbox(
            storageNamespace: accountB,
            applicationSupportDirectory: applicationSupport
        )

        #expect(await outboxA.all(bookId: "book", chapterN: 1).isEmpty)
        #expect(await outboxB.all(bookId: "book", chapterN: 1).isEmpty)
        #expect(try Data(contentsOf: legacyURL) == legacyData)
    }

    @Test("invalid namespace fails with a value-free error and creates no path")
    func invalidNamespaceFailsClosedAndRedacted() {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appending(path: "ReflectionInvalidNamespace-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let rawValue = "../private-account@example.test"

        #expect(throws: SocialPrivateStorageFailure.invalidStorageNamespace) {
            _ = try ReflectionOutbox(
                storageNamespace: rawValue,
                applicationSupportDirectory: applicationSupport
            )
        }
        #expect(!FileManager.default.fileExists(atPath: applicationSupport.path))
        let error = SocialPrivateStorageFailure.invalidStorageNamespace
        #expect(!String(describing: error).contains(rawValue))
        #expect(Mirror(reflecting: error).children.isEmpty)
    }

    @Test("corrupt account outbox fails closed instead of appearing empty")
    func corruptScopedOutboxFailsClosed() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appending(path: "ReflectionCorruptOutbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let accountDirectory = applicationSupport
            .appending(path: "com.chapterflow", directoryHint: .isDirectory)
            .appending(path: "accounts", directoryHint: .isDirectory)
            .appending(path: accountA, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: accountDirectory.appending(path: "pending_reflections.json")
        )

        #expect(throws: SocialPrivateStorageFailure.unreadableReflectionOutbox) {
            _ = try ReflectionOutbox(
                storageNamespace: accountA,
                applicationSupportDirectory: applicationSupport
            )
        }
    }
}

// MARK: - ReflectionDisplayItem tests

@Suite("ReflectionDisplayItem")
struct ReflectionDisplayItemTests {

    @Test("pending item reports isLocalPending correctly")
    func pendingItemIsLocalPending() {
        let item = PendingReflectionItem(bookId: "bk", chapterN: 1, text: "Test", syncState: .pending)
        let display = ReflectionDisplayItem.pending(item)
        #expect(display.isLocalPending)
        #expect(!display.hasFeedback)
    }

    @Test("synced item is not local pending")
    func syncedItemNotLocalPending() {
        let refl = ChapterReflection(
            reflectionId: "r1", bookId: "bk", chapterN: 1,
            text: "Text", createdAt: Date()
        )
        let display = ReflectionDisplayItem.synced(refl)
        #expect(!display.isLocalPending)
    }

    @Test("feedbackText proxied from pending item")
    func feedbackTextFromPending() {
        var item = PendingReflectionItem(bookId: "bk", chapterN: 1, text: "Hi")
        item.feedbackText = "Good job!"
        let display = ReflectionDisplayItem.pending(item)
        #expect(display.feedbackText == "Good job!")
        #expect(display.hasFeedback)
    }

    @Test("feedbackText proxied from synced reflection")
    func feedbackTextFromSynced() {
        let refl = ChapterReflection(
            reflectionId: "r1", bookId: "bk", chapterN: 1,
            text: "Text", createdAt: Date(), feedbackText: "Excellent!"
        )
        let display = ReflectionDisplayItem.synced(refl)
        #expect(display.feedbackText == "Excellent!")
        #expect(display.hasFeedback)
    }

    @Test("isFeedbackLoading only true for pending item with feedbackState == .pending")
    func isFeedbackLoadingState() {
        var item = PendingReflectionItem(bookId: "bk", chapterN: 1, text: "Hi")
        item.feedbackState = .pending
        let display = ReflectionDisplayItem.pending(item)
        #expect(display.isFeedbackLoading)
    }

    @Test("serverReflectionId from synced uses reflectionId")
    func serverReflectionIdFromSynced() {
        let refl = ChapterReflection(
            reflectionId: "srv-abc", bookId: "bk", chapterN: 1,
            text: "Text", createdAt: Date()
        )
        let display = ReflectionDisplayItem.synced(refl)
        #expect(display.serverReflectionId == "srv-abc")
    }
}
