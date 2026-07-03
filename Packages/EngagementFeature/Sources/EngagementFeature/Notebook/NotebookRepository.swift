import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "notebook")

// MARK: - Pending mutation types

/// Kinds of notebook mutations queued for offline sync.
enum PendingMutationKind: String, Codable {
    case editEntry
    case deleteEntry
    case savedToggle
}

/// A notebook mutation queued while offline. Stored as JSON in CachedKeyValue.
struct PendingNotebookMutation: Codable, Sendable, Identifiable {
    let id: String
    let kind: PendingMutationKind
    let entryId: String?
    let bookId: String?
    let updateContent: String?
    let updateTags: [String]?
    let savedValue: Bool?
    let createdAt: Date
}

// MARK: - Cache keys

private enum NotebookCacheKey {
    static let entries = "notebook.entries"
    static let savedBookIds = "notebook.savedBookIds"
    static let pendingMutations = "notebook.pendingMutations"
}

// MARK: - NotebookRepository

/// The data layer for the Notebook + Saved hub (P5.8).
///
/// Reads `GET /book/me/notebook` and `GET /book/me/saved`; writes
/// edits/deletes/saved-toggles online; queues them offline via a lightweight
/// JSON outbox stored in `CachedKeyValue` and drains on reconnect.
public actor NotebookRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?

    // MARK: In-memory cache

    private struct MemEntry<T: Sendable> {
        let value: T
        let storedAt: Date
        func isStale(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) >= ttl
        }
    }

    private var memEntries: MemEntry<[NotebookEntry]>?
    private var memSavedIds: MemEntry<[String]>?
    private let entriesTTL: TimeInterval = 3 * 60
    private let savedTTL: TimeInterval = 5 * 60

    // MARK: Init

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch notebook entries

    public func fetchEntries(forceRefresh: Bool = false) async throws -> [NotebookEntry] {
        if !forceRefresh, let entry = memEntries, !entry.isStale(ttl: entriesTTL) {
            return entry.value
        }
        do {
            let resp: NotebookResponse = try await apiClient.send(Endpoints.getNotebook())
            let entries = resp.entries
            memEntries = MemEntry(value: entries, storedAt: Date())
            persistEntriesOnDisk(entries)
            return entries
        } catch AppError.offline {
            if let cached = loadEntriesFromDisk() {
                memEntries = MemEntry(value: cached, storedAt: Date())
                return cached
            }
            if let entry = memEntries { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Fetch saved book IDs

    public func fetchSavedBookIds(forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh, let entry = memSavedIds, !entry.isStale(ttl: savedTTL) {
            return entry.value
        }
        do {
            let resp: SavedBooksResponse = try await apiClient.send(Endpoints.getSavedBooks())
            let ids = resp.savedBookIds
            memSavedIds = MemEntry(value: ids, storedAt: Date())
            persistSavedIdsOnDisk(ids)
            return ids
        } catch AppError.offline {
            if let cached = loadSavedIdsFromDisk() {
                memSavedIds = MemEntry(value: cached, storedAt: Date())
                return cached
            }
            if let entry = memSavedIds { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Edit entry

    /// Edit an entry's content and/or tags.
    ///
    /// Online: PATCH immediately and refresh the in-memory entry.
    /// Offline: apply optimistically to the cache and enqueue.
    @discardableResult
    public func editEntry(
        entryId: String,
        content: String?,
        tags: [String]?
    ) async throws -> NotebookEntry {
        let body = NotebookUpdateRequest(content: content, tags: tags)
        do {
            let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
            let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
            // Refresh full list to get updated entry
            let updated = try await fetchEntries(forceRefresh: true)
            return updated.first { $0.entryId == entryId } ?? makeOptimisticEntry(
                entryId: entryId, content: content, tags: tags
            )
        } catch AppError.offline {
            enqueueEdit(entryId: entryId, content: content, tags: tags)
            let patched = applyOptimisticEdit(entryId: entryId, content: content, tags: tags)
            return patched
        }
    }

    // MARK: - Delete entry

    public func deleteEntry(entryId: String) async throws {
        do {
            let _: NotebookDeleteResponse = try await apiClient.send(
                Endpoints.deleteNotebookEntry(entryId: entryId)
            )
            removeEntryFromCache(entryId: entryId)
        } catch AppError.offline {
            enqueueDelete(entryId: entryId)
            removeEntryFromCache(entryId: entryId)
        }
    }

    // MARK: - Toggle saved

    @discardableResult
    public func toggleSaved(bookId: String, saved: Bool) async throws -> [String] {
        do {
            let endpoint = try Endpoints.toggleSaved(bookId: bookId, saved: saved)
            let resp: SavedBooksResponse = try await apiClient.send(endpoint)
            let ids = resp.savedBookIds
            memSavedIds = MemEntry(value: ids, storedAt: Date())
            persistSavedIdsOnDisk(ids)
            return ids
        } catch AppError.offline {
            enqueueSavedToggle(bookId: bookId, saved: saved)
            let optimistic = applySavedToggle(bookId: bookId, saved: saved)
            return optimistic
        }
    }

    // MARK: - Drain pending mutations

    /// Replay queued offline mutations against the API. Call when connectivity returns.
    public func drainPendingMutations() async {
        var mutations = loadPendingMutations()
        guard !mutations.isEmpty else { return }
        var remaining: [PendingNotebookMutation] = []
        for mutation in mutations {
            do {
                switch mutation.kind {
                case .editEntry:
                    guard let entryId = mutation.entryId else { continue }
                    let body = NotebookUpdateRequest(
                        content: mutation.updateContent,
                        tags: mutation.updateTags
                    )
                    let endpoint = try Endpoints.patchNotebookEntry(entryId: entryId, body: body)
                    let _: NotebookUpdateResponse = try await apiClient.send(endpoint)
                case .deleteEntry:
                    guard let entryId = mutation.entryId else { continue }
                    let _: NotebookDeleteResponse = try await apiClient.send(
                        Endpoints.deleteNotebookEntry(entryId: entryId)
                    )
                case .savedToggle:
                    guard let bookId = mutation.bookId,
                          let saved = mutation.savedValue else { continue }
                    let endpoint = try Endpoints.toggleSaved(bookId: bookId, saved: saved)
                    let _: SavedBooksResponse = try await apiClient.send(endpoint)
                }
            } catch AppError.offline {
                remaining.append(mutation)
            } catch {
                log.warning("Notebook mutation drain failed: \(error)")
                // Don't re-queue non-offline errors (e.g. 404 not found)
            }
        }
        mutations = remaining
        savePendingMutations(remaining)
        // Refresh caches after drain
        if remaining.count < mutations.count {
            _ = try? await fetchEntries(forceRefresh: true)
            _ = try? await fetchSavedBookIds(forceRefresh: true)
        }
    }

    // MARK: - Cache invalidation

    public func invalidateAll() {
        memEntries = nil
        memSavedIds = nil
    }

    // MARK: - Pending mutations count

    public var pendingMutationCount: Int {
        loadPendingMutations().count
    }

    // MARK: - Private helpers

    private func removeEntryFromCache(entryId: String) {
        if var entries = memEntries?.value {
            entries.removeAll { $0.entryId == entryId }
            memEntries = MemEntry(value: entries, storedAt: Date())
            persistEntriesOnDisk(entries)
        }
    }

    private func applyOptimisticEdit(
        entryId: String,
        content: String?,
        tags: [String]?
    ) -> NotebookEntry {
        guard var entries = memEntries?.value,
              let idx = entries.firstIndex(where: { $0.entryId == entryId }) else {
            return makeOptimisticEntry(entryId: entryId, content: content, tags: tags)
        }
        let old = entries[idx]
        let patched = NotebookEntry(
            entryId: old.entryId,
            bookId: old.bookId,
            chapterId: old.chapterId,
            type: old.type,
            content: content ?? old.content,
            quote: old.quote,
            createdAt: old.createdAt,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            bookTitle: old.bookTitle,
            chapterTitle: old.chapterTitle,
            chapterNumber: old.chapterNumber,
            tags: tags ?? old.tags
        )
        entries[idx] = patched
        memEntries = MemEntry(value: entries, storedAt: Date())
        persistEntriesOnDisk(entries)
        return patched
    }

    private func makeOptimisticEntry(
        entryId: String,
        content: String?,
        tags: [String]?
    ) -> NotebookEntry {
        NotebookEntry(
            entryId: entryId,
            bookId: "",
            chapterId: nil,
            type: .note,
            content: content,
            quote: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            bookTitle: nil,
            chapterTitle: nil,
            chapterNumber: nil,
            tags: tags
        )
    }

    private func applySavedToggle(bookId: String, saved: Bool) -> [String] {
        var ids = memSavedIds?.value ?? []
        if saved {
            if !ids.contains(bookId) { ids.append(bookId) }
        } else {
            ids.removeAll { $0 == bookId }
        }
        memSavedIds = MemEntry(value: ids, storedAt: Date())
        persistSavedIdsOnDisk(ids)
        return ids
    }

    // MARK: - Outbox helpers

    private func enqueueEdit(entryId: String, content: String?, tags: [String]?) {
        var mutations = loadPendingMutations()
        // Replace earlier edit for same entry
        mutations.removeAll { $0.kind == .editEntry && $0.entryId == entryId }
        mutations.append(PendingNotebookMutation(
            id: UUID().uuidString,
            kind: .editEntry,
            entryId: entryId,
            bookId: nil,
            updateContent: content,
            updateTags: tags,
            savedValue: nil,
            createdAt: Date()
        ))
        savePendingMutations(mutations)
    }

    private func enqueueDelete(entryId: String) {
        var mutations = loadPendingMutations()
        // A delete supersedes any queued edits for this entry
        mutations.removeAll { $0.entryId == entryId }
        mutations.append(PendingNotebookMutation(
            id: UUID().uuidString,
            kind: .deleteEntry,
            entryId: entryId,
            bookId: nil,
            updateContent: nil,
            updateTags: nil,
            savedValue: nil,
            createdAt: Date()
        ))
        savePendingMutations(mutations)
    }

    private func enqueueSavedToggle(bookId: String, saved: Bool) {
        var mutations = loadPendingMutations()
        // Replace earlier toggle for same book
        mutations.removeAll { $0.kind == .savedToggle && $0.bookId == bookId }
        mutations.append(PendingNotebookMutation(
            id: UUID().uuidString,
            kind: .savedToggle,
            entryId: nil,
            bookId: bookId,
            updateContent: nil,
            updateTags: nil,
            savedValue: saved,
            createdAt: Date()
        ))
        savePendingMutations(mutations)
    }

    private func loadPendingMutations() -> [PendingNotebookMutation] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)
        let key = NotebookCacheKey.pendingMutations
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first,
              let data = entry.value.data(using: .utf8) else { return [] }
        return (try? JSONCoding.decoder.decode([PendingNotebookMutation].self, from: data)) ?? []
    }

    private func savePendingMutations(_ mutations: [PendingNotebookMutation]) {
        guard let container = modelContainer else { return }
        guard let data = try? JSONCoding.encoder.encode(mutations),
              let json = String(data: data, encoding: .utf8) else { return }
        writeCachedKeyValue(key: NotebookCacheKey.pendingMutations, value: json, container: container)
    }

    // MARK: - Disk cache

    private func persistEntriesOnDisk(_ entries: [NotebookEntry]) {
        guard let container = modelContainer else { return }
        // We cannot encode NotebookResponse directly (no init), so wrap manually
        struct Wrapper: Encodable { let entries: [NotebookEntry] }
        guard let data = try? JSONCoding.encoder.encode(Wrapper(entries: entries)),
              let json = String(data: data, encoding: .utf8) else { return }
        writeCachedKeyValue(key: NotebookCacheKey.entries, value: json, container: container)
    }

    private func loadEntriesFromDisk() -> [NotebookEntry]? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let key = NotebookCacheKey.entries
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first,
              let data = entry.value.data(using: .utf8) else { return nil }
        struct Wrapper: Decodable { let entries: [NotebookEntry] }
        return (try? JSONCoding.decoder.decode(Wrapper.self, from: data))?.entries
    }

    private func persistSavedIdsOnDisk(_ ids: [String]) {
        guard let container = modelContainer else { return }
        guard let data = try? JSONCoding.encoder.encode(ids),
              let json = String(data: data, encoding: .utf8) else { return }
        writeCachedKeyValue(key: NotebookCacheKey.savedBookIds, value: json, container: container)
    }

    private func loadSavedIdsFromDisk() -> [String]? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let key = NotebookCacheKey.savedBookIds
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first,
              let data = entry.value.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode([String].self, from: data)
    }

    private func writeCachedKeyValue(key: String, value: String, container: ModelContainer) {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CachedKeyValue>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.value = value
            existing.updatedAt = Date()
        } else {
            context.insert(CachedKeyValue(key: key, value: value))
        }
        do {
            try context.save()
        } catch {
            log.warning("Notebook cache write failed for '\(key)': \(error)")
        }
    }
}
