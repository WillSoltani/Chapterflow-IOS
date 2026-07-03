import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - NotebookRepository Tests

@Suite("NotebookRepository")
struct NotebookRepositoryTests {

    // MARK: - Helpers

    /// Makes a repository backed by a stub client that returns the given fixtures.
    private func makeRepository(
        entries: [NotebookEntry] = NotebookEntry.previewEntries,
        savedIds: [String] = ["atomic-habits"]
    ) -> NotebookRepository {
        let client = StubNotebookClient(entries: entries, savedIds: savedIds)
        return NotebookRepository(apiClient: client, modelContainer: nil)
    }

    // MARK: - Fetch entries

    @Test("fetchEntries returns all entries from the server")
    func fetchEntriesReturnsAll() async throws {
        let repo = makeRepository()
        let entries = try await repo.fetchEntries()
        #expect(entries.count == NotebookEntry.previewEntries.count)
    }

    @Test("fetchEntries uses memory cache within TTL")
    func fetchEntriesUsesCache() async throws {
        let counter = Counter()
        let client = CountingStubClient(entries: NotebookEntry.previewEntries, counter: counter)
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        _ = try await repo.fetchEntries()
        _ = try await repo.fetchEntries()  // should hit cache
        #expect(await counter.callCount == 1)
    }

    @Test("fetchEntries respects forceRefresh")
    func fetchEntriesForceRefresh() async throws {
        let counter = Counter()
        let client = CountingStubClient(entries: NotebookEntry.previewEntries, counter: counter)
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        _ = try await repo.fetchEntries()
        _ = try await repo.fetchEntries(forceRefresh: true)
        #expect(await counter.callCount == 2)
    }

    // MARK: - Fetch saved IDs

    @Test("fetchSavedBookIds returns server list")
    func fetchSavedBookIds() async throws {
        let repo = makeRepository(savedIds: ["book-a", "book-b"])
        let ids = try await repo.fetchSavedBookIds()
        #expect(ids == ["book-a", "book-b"])
    }

    // MARK: - Toggle saved

    @Test("toggleSaved adds an ID when saved=true")
    func toggleSavedTrue() async throws {
        let repo = makeRepository(savedIds: [])
        let ids = try await repo.toggleSaved(bookId: "new-book", saved: true)
        #expect(ids.contains("new-book"))
    }

    @Test("toggleSaved removes an ID when saved=false")
    func toggleSavedFalse() async throws {
        let repo = makeRepository(savedIds: ["existing-book"])
        let ids = try await repo.toggleSaved(bookId: "existing-book", saved: false)
        #expect(!ids.contains("existing-book"))
    }

    // MARK: - Delete entry (optimistic, no disk)

    @Test("deleteEntry removes entry from memory cache")
    func deleteEntryRemovesFromCache() async throws {
        let repo = makeRepository()
        _ = try await repo.fetchEntries()  // populate cache
        let before = try await repo.fetchEntries()
        let target = before[0].entryId
        try await repo.deleteEntry(entryId: target)
        let after = try await repo.fetchEntries()  // still from cache
        #expect(!after.map(\.entryId).contains(target))
    }

    // MARK: - Offline: fallback on AppError.offline

    @Test("fetchEntries throws offline when no cache available")
    func fetchEntriesThrowsOfflineWhenNoCache() async throws {
        let client = OfflineStubClient()
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        do {
            _ = try await repo.fetchEntries()
            Issue.record("Expected offline error")
        } catch AppError.offline {
            // expected
        }
    }

    // MARK: - Edit entry

    @Test("editEntry applies optimistic patch when offline")
    func editEntryOptimistic() async throws {
        // PartialOfflineStub succeeds for GET /book/me/notebook but throws .offline for PATCH.
        // This seeds the cache then forces the offline code path for the edit.
        let client = PartialOfflineStubClient(entries: NotebookEntry.previewEntries)
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        _ = try await repo.fetchEntries()  // populate memory cache

        let entry = NotebookEntry.previewEntries[0]
        let patched = try await repo.editEntry(
            entryId: entry.entryId,
            content: "Updated content",
            tags: ["new-tag"]
        )
        #expect(patched.content == "Updated content")
    }
}

// MARK: - Pending mutation outbox tests

@Suite("NotebookRepository — outbox")
struct NotebookOutboxTests {

    @Test("pendingMutationCount is zero on fresh repo (no disk)")
    func pendingMutationCountInitial() async {
        let client = StubNotebookClient(entries: [], savedIds: [])
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        let count = await repo.pendingMutationCount
        #expect(count == 0)
    }

    @Test("drainPendingMutations completes without throwing on empty queue")
    func drainEmptyQueue() async {
        let client = StubNotebookClient(entries: [], savedIds: [])
        let repo = NotebookRepository(apiClient: client, modelContainer: nil)
        await repo.drainPendingMutations()  // must not throw / crash
    }
}

// MARK: - Stub encoding types (file-level to avoid nested-in-generic errors)

private struct StubEntriesWrap: Encodable { let entries: [NotebookEntry] }
private struct StubSavedWrap: Encodable { let savedBookIds: [String] }
private struct StubToggleBody: Decodable { let bookId: String; let saved: Bool }
private struct StubDeleteResp: Encodable { let deleted: Bool? }
private struct StubPatchResp: Encodable {
    let entry: Inner
    struct Inner: Encodable {
        let entryId: String
        let content: String?
        let tags: [String]?
        let updatedAt: String
    }
}

// MARK: - Stubs

private final class StubNotebookClient: APIClientProtocol, @unchecked Sendable {
    let entries: [NotebookEntry]
    let savedIds: [String]

    init(entries: [NotebookEntry], savedIds: [String]) {
        self.entries = entries
        self.savedIds = savedIds
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data: Data
        switch endpoint.path {
        case "/book/me/notebook" where endpoint.method == .get:
            data = try JSONCoding.encoder.encode(StubEntriesWrap(entries: entries))
        case "/book/me/saved" where endpoint.method == .get:
            data = try JSONCoding.encoder.encode(StubSavedWrap(savedBookIds: savedIds))
        case "/book/me/saved" where endpoint.method == .post:
            var updated = savedIds
            if let raw = endpoint.httpBody,
               let req = try? JSONCoding.decoder.decode(StubToggleBody.self, from: raw) {
                if req.saved {
                    if !updated.contains(req.bookId) { updated.append(req.bookId) }
                } else {
                    updated.removeAll { $0 == req.bookId }
                }
            }
            data = try JSONCoding.encoder.encode(StubSavedWrap(savedBookIds: updated))
        case _ where endpoint.method == .patch:
            data = try JSONCoding.encoder.encode(
                StubPatchResp(entry: .init(entryId: "x", content: nil, tags: nil, updatedAt: "2026-07-03T00:00:00Z"))
            )
        case _ where endpoint.method == .delete:
            data = try JSONCoding.encoder.encode(StubDeleteResp(deleted: true))
        default:
            throw AppError.notFound
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private actor Counter {
    var callCount = 0
    func increment() { callCount += 1 }
}

private final class CountingStubClient: APIClientProtocol, @unchecked Sendable {
    let entries: [NotebookEntry]
    let counter: Counter

    init(entries: [NotebookEntry], counter: Counter) {
        self.entries = entries
        self.counter = counter
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        await counter.increment()
        let data = try JSONCoding.encoder.encode(StubEntriesWrap(entries: entries))
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private final class OfflineStubClient: APIClientProtocol, @unchecked Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        throw AppError.offline
    }
}

/// Succeeds for GET /book/me/notebook; throws .offline for everything else.
/// Used to seed the memory cache, then force the offline code path for mutations.
private final class PartialOfflineStubClient: APIClientProtocol, @unchecked Sendable {
    let entries: [NotebookEntry]

    init(entries: [NotebookEntry]) {
        self.entries = entries
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        if endpoint.method == .get && endpoint.path == "/book/me/notebook" {
            let data = try JSONCoding.encoder.encode(StubEntriesWrap(entries: entries))
            return try JSONCoding.decoder.decode(T.self, from: data)
        }
        throw AppError.offline
    }
}
