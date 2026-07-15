import Foundation
import SwiftData
import Models
import Networking
import Persistence
import CoreKit
import os

/// Main-actor owner for the non-Sendable UserDefaults-backed position store.
@MainActor
private final class ReaderPositionStore {
    private let storage: KeyValueStore

    init(_ store: KeyValueStore) {
        storage = store
    }

    func set(_ value: Int, forKey key: String) throws {
        try storage.set(value, forKey: key)
    }

    func value(forKey key: String) -> Int? {
        storage.value(Int.self, forKey: key)
    }
}

// MARK: - Live implementation

/// Production `ReaderRepository` — cache-first, offline-capable.
///
/// **Read-through cache strategy**
/// - `getChapter`: reads from ``CachedChapter`` first; background-fetches when
///   online. Throws ``AppError/offline`` when no cache and the device is offline.
/// - `getBookState`: reads from ``CachedBookState`` first; background-fetches when
///   online.
/// - Cursor patches are queued as ``MutationKind/progressCursor`` when offline.
/// - Session events (heartbeat, start, end) are fire-and-forget; silently dropped
///   when offline.
///
public struct LiveReaderRepository: ReaderRepository, Sendable {
    private let client: any APIClientProtocol
    private let positionStore: ReaderPositionStore
    private let container: ModelContainer?
    private let reachability: ReachabilityService
    private let accountID: String
    private let workPermit: SessionWorkPermit
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "ReaderRepository")

    @MainActor
    public init(
        client: any APIClientProtocol,
        store: KeyValueStore = KeyValueStore(),
        container: ModelContainer? = nil,
        reachability: ReachabilityService,
        accountID: String,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.client = client
        self.positionStore = ReaderPositionStore(store)
        self.container = container
        self.reachability = reachability
        self.accountID = accountID
        self.workPermit = workPermit
    }

    // MARK: - Chapter loading

    public func getChapter(bookId: String, n: Int, mode: String?) async throws -> ChapterResponse {
        let ticket = try workPermit.begin()
        // Cache-first: serve any cached chapter immediately.
        if let cached = try loadCachedChapter(bookId: bookId, n: n) {
            if reachability.isConnectedSync {
                Task {
                    try? await fetchAndCacheChapter(
                        bookId: bookId,
                        n: n,
                        mode: mode,
                        ticket: ticket
                    )
                }
            }
            return cached
        }
        guard reachability.isConnectedSync else { throw AppError.offline }
        return try await fetchAndCacheChapter(bookId: bookId, n: n, mode: mode, ticket: ticket)
    }

    private func loadCachedChapter(bookId: String, n: Int) throws -> ChapterResponse? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        // Use the composite rowId (has @Attribute(.unique) → SQLite index) instead of
        // querying on bookId+number, which are unindexed columns and force a table scan.
        let uid = accountID
        let rowId = CachedChapter.makeRowId(userId: uid, bookId: bookId, number: n)
        let descriptor = FetchDescriptor<CachedChapter>(predicate: #Predicate { $0.rowId == rowId })
        guard let row = try ctx.fetch(descriptor).first else { return nil }
        let chapter = try row.toDomain()
        let progress = try loadCachedProgress(bookId: bookId, userId: uid, ctx: ctx)
            ?? .placeholder(chapterNumber: n)
        return ChapterResponse(chapter: chapter, progress: progress)
    }

    // userId is threaded from the caller so both reads hit the same indexed rowId format.
    private func loadCachedProgress(bookId: String, userId: String, ctx: ModelContext) throws -> BookProgress? {
        // rowId format mirrors the write path: "\(userId):\(bookId)" with @Attribute(.unique).
        let rowId = "\(userId):\(bookId)"
        let descriptor = FetchDescriptor<CachedProgress>(predicate: #Predicate { $0.rowId == rowId })
        return try ctx.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    @discardableResult
    private func fetchAndCacheChapter(
        bookId: String,
        n: Int,
        mode: String?,
        ticket: UInt64
    ) async throws -> ChapterResponse {
        let endpoint = Endpoints.getChapter(bookId: bookId, n: n, mode: mode)
        let response: ChapterResponse = try await client.send(endpoint)
        if let container {
            try workPermit.commit(ticket) {
                try cacheChapterResponse(response, bookId: bookId, n: n, in: container)
            }
        }
        return response
    }

    private func cacheChapterResponse(
        _ response: ChapterResponse,
        bookId: String,
        n: Int,
        in container: ModelContainer
    ) throws {
        let ctx = ModelContext(container)
        let uid = accountID

        // Cache the chapter content.
        let rowId = CachedChapter.makeRowId(userId: uid, bookId: bookId, number: n)
        let chapterDescriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        let chapterData = try JSONEncoder().encode(response.chapter)
        let chapterJSON = String(bytes: chapterData, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(chapterDescriptor).first {
            existing.dataJSON = chapterJSON
            existing.cachedAt = Date()
        } else {
            let row = CachedChapter(
                rowId: rowId,
                userId: uid,
                bookId: bookId,
                number: n,
                dataJSON: chapterJSON
            )
            ctx.insert(row)
        }

        // Cache progress alongside the chapter.
        try cacheProgress(response.progress, bookId: bookId, userId: uid, ctx: ctx)

        try ctx.save()
    }

    private func cacheProgress(
        _ progress: BookProgress,
        bookId: String,
        userId: String,
        ctx: ModelContext
    ) throws {
        let rowId = "\(userId):\(bookId)"
        let descriptor = FetchDescriptor<CachedProgress>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        let data = try JSONEncoder().encode(progress)
        let json = String(bytes: data, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(descriptor).first {
            existing.dataJSON = json
            existing.cachedAt = Date()
        } else {
            ctx.insert(CachedProgress(
                rowId: rowId,
                userId: userId,
                bookId: bookId,
                dataJSON: json
            ))
        }
    }

    // MARK: - Cursor patch

    public func patchBookCursor(bookId: String, chapterId: String) async throws {
        let ticket = try workPermit.begin()
        guard reachability.isConnectedSync else {
            // Queue cursor update for sync when back online.
            try workPermit.commit(ticket) {
                try enqueueCursorMutation(bookId: bookId, chapterId: chapterId)
            }
            return
        }
        let endpoint = try Endpoints.patchBookCursor(bookId: bookId, chapterId: chapterId)
        let _: BookStateResponse = try await client.send(endpoint)
    }

    private func enqueueCursorMutation(bookId: String, chapterId: String) throws {
        guard let container else { return }
        let ctx = ModelContext(container)
        let uid = accountID
        struct CursorPayload: Codable {
            let bookId: String
            let chapterId: String
        }
        let mutation = try PendingMutation.make(
            userId: uid,
            kind: .progressCursor,
            payload: CursorPayload(bookId: bookId, chapterId: chapterId)
        )
        ctx.insert(mutation)
        try ctx.save()
    }

    // MARK: - Session lifecycle

    public func startReadingSession(bookId: String, chapterId: String) async -> String? {
        guard reachability.isConnectedSync else { return nil }
        do {
            let endpoint = try Endpoints.postReadingSessionEvent(
                event: "start",
                bookId: bookId,
                chapterId: chapterId,
                sessionId: nil
            )
            let response: ReadingSessionResponse = try await client.send(endpoint)
            return response.sessionId
        } catch {
            logger.debug("Reading session start failed (suppressed): \(error.localizedDescription)")
            return nil
        }
    }

    public func postReadingHeartbeat(bookId: String, chapterId: String, sessionId: String?) async {
        guard reachability.isConnectedSync else { return }
        do {
            let endpoint = try Endpoints.postReadingSessionEvent(
                event: "heartbeat",
                bookId: bookId,
                chapterId: chapterId,
                sessionId: sessionId
            )
            let _: ReadingSessionResponse = try await client.send(endpoint)
        } catch {
            logger.debug("Reading heartbeat failed (suppressed): \(error.localizedDescription)")
        }
    }

    public func endReadingSession(bookId: String, chapterId: String, sessionId: String?) async {
        guard reachability.isConnectedSync else { return }
        do {
            let endpoint = try Endpoints.postReadingSessionEvent(
                event: "end",
                bookId: bookId,
                chapterId: chapterId,
                sessionId: sessionId
            )
            let _: ReadingSessionResponse = try await client.send(endpoint)
        } catch {
            logger.debug("Reading session end failed (suppressed): \(error.localizedDescription)")
        }
    }

    // MARK: - Book state

    public func getBookState(bookId: String) async throws -> BookStateResponse {
        let ticket = try workPermit.begin()
        if let cached = try loadCachedBookState(bookId: bookId) {
            if reachability.isConnectedSync {
                Task { try? await fetchAndCacheBookState(bookId: bookId, ticket: ticket) }
            }
            return cached
        }
        guard reachability.isConnectedSync else { throw AppError.offline }
        return try await fetchAndCacheBookState(bookId: bookId, ticket: ticket)
    }

    private func loadCachedBookState(bookId: String) throws -> BookStateResponse? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        // Use indexed rowId (same format as the write path) to avoid a full table scan.
        let uid = accountID
        let rowId = "\(uid):\(bookId)"
        let descriptor = FetchDescriptor<CachedBookState>(predicate: #Predicate { $0.rowId == rowId })
        return try ctx.fetch(descriptor).first.flatMap { try? $0.toDomain() }
    }

    @discardableResult
    private func fetchAndCacheBookState(
        bookId: String,
        ticket: UInt64
    ) async throws -> BookStateResponse {
        let endpoint = Endpoints.getBookState(bookId: bookId)
        let response: BookStateResponse = try await client.send(endpoint)
        if let container {
            try workPermit.commit(ticket) {
                try storeBookState(response, bookId: bookId, in: container)
            }
        }
        return response
    }

    private func storeBookState(
        _ response: BookStateResponse,
        bookId: String,
        in container: ModelContainer
    ) throws {
        let ctx = ModelContext(container)
        let uid = accountID
        let rowId = "\(uid):\(bookId)"
        let descriptor = FetchDescriptor<CachedBookState>(
            predicate: #Predicate { $0.rowId == rowId }
        )
        let data = try JSONEncoder().encode(response)
        let json = String(bytes: data, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(descriptor).first {
            existing.dataJSON = json
            existing.cachedAt = Date()
        } else {
            ctx.insert(CachedBookState(
                rowId: rowId,
                userId: uid,
                bookId: bookId,
                dataJSON: json
            ))
        }
        try ctx.save()
    }

    // MARK: - Book manifest

    public func getBookManifest(bookId: String) async throws -> BookManifest {
        try await client.send(Endpoints.getBook(id: bookId))
    }

    // MARK: - Position persistence

    @MainActor
    public func saveScrollPosition(bookId: String, chapterNumber: Int, blockIndex: Int) {
        guard let ticket = try? workPermit.begin() else { return }
        let key = positionKey(bookId: bookId, chapterNumber: chapterNumber)
        try? workPermit.commit(ticket) {
            try positionStore.set(blockIndex, forKey: key)
        }
    }

    @MainActor
    public func loadScrollPosition(bookId: String, chapterNumber: Int) -> Int? {
        let key = positionKey(bookId: bookId, chapterNumber: chapterNumber)
        return positionStore.value(forKey: key)
    }

    // MARK: - Private

    private func positionKey(bookId: String, chapterNumber: Int) -> String {
        "reader.position.v1.\(accountID).\(bookId).\(chapterNumber)"
    }
}

// MARK: - BookProgress placeholder

private extension BookProgress {
    static func placeholder(chapterNumber: Int) -> BookProgress {
        BookProgress(
            currentChapterNumber: chapterNumber,
            unlockedThroughChapterNumber: chapterNumber,
            completedChapters: [],
            bestScoreByChapter: [:],
            preferredVariant: nil,
            progressRev: nil
        )
    }
}

// MARK: - Response types

/// Response from `POST /book/me/reading-sessions`.
struct ReadingSessionResponse: Decodable, Sendable {
    let sessionId: String?
}
