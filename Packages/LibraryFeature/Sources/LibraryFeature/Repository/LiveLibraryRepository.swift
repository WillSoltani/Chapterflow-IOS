import Foundation
import SwiftData
import Models
import Networking
import Persistence
import CoreKit

/// Production ``LibraryRepository`` — cache-first, offline-capable.
///
/// **Read-through cache strategy (stale-while-revalidate)**
/// 1. Serve any cached data immediately (even if stale).
/// 2. If online and the cache is stale, kick off a silent background refresh.
/// 3. If no cached data exists and the device is offline, throw
///    ``AppError/offline`` so the caller can show ``CacheMissView``.
public actor LiveLibraryRepository: LibraryRepository {

    private let client: any APIClientProtocol
    private let container: ModelContainer?
    private let reachability: ReachabilityService

    private static let catalogCacheKey = "library.catalog.v1"
    private static let searchIndexCacheKey = "library.searchIndex.v1"
    private static let catalogTTL: TimeInterval = 300
    private static let searchIndexTTL: TimeInterval = 1800

    public init(
        client: any APIClientProtocol,
        container: ModelContainer? = nil,
        reachability: ReachabilityService
    ) {
        self.client = client
        self.container = container
        self.reachability = reachability
    }

    // MARK: - Catalog

    public func getCatalog() async throws -> [BookCatalogItem] {
        if let cached = try loadCachedCatalog(allowStale: true) {
            // Serve stale cache immediately; refresh in background when online + stale.
            if reachability.isConnectedSync && isCatalogStale() {
                Task { try? await fetchAndCacheCatalog() }
            }
            return cached
        }
        guard reachability.isConnectedSync else { throw AppError.offline }
        return try await fetchAndCacheCatalog()
    }

    private func isCatalogStale() -> Bool {
        guard let container else { return true }
        let ctx = ModelContext(container)
        let key = Self.catalogCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(predicate: #Predicate { $0.key == key })
        guard let record = try? ctx.fetch(descriptor).first else { return true }
        return Date().timeIntervalSince(record.updatedAt) >= Self.catalogTTL
    }

    private func loadCachedCatalog(allowStale: Bool) throws -> [BookCatalogItem]? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        let key = Self.catalogCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(predicate: #Predicate { $0.key == key })
        guard let record = try ctx.fetch(descriptor).first else { return nil }
        if !allowStale {
            guard Date().timeIntervalSince(record.updatedAt) < Self.catalogTTL else { return nil }
        }
        guard let data = record.value.data(using: .utf8) else { return nil }
        return try JSONCoding.decoder.decode(CatalogResponse.self, from: data).books
    }

    @discardableResult
    private func fetchAndCacheCatalog() async throws -> [BookCatalogItem] {
        let response: CatalogResponse = try await client.send(Endpoints.getBooks())
        if let container {
            try storeCatalog(response, in: container)
        }
        return response.books
    }

    private func storeCatalog(_ response: CatalogResponse, in container: ModelContainer) throws {
        let ctx = ModelContext(container)
        let key = Self.catalogCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        let encoded = try JSONCoding.encoder.encode(response)
        let value = String(data: encoded, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(descriptor).first {
            existing.value = value
            existing.updatedAt = Date()
        } else {
            ctx.insert(CachedKeyValue(key: key, value: value))
        }
        try ctx.save()
    }

    // MARK: - Progress overview

    public func getProgressOverview() async throws -> ProgressOverviewResponse {
        guard reachability.isConnectedSync else {
            return ProgressOverviewResponse(progress: [])
        }
        let response: ProgressOverviewResponse = try await client.send(
            Endpoints.getProgressOverview())
        return enrichWithChapterTotals(response)
    }

    /// The deployed progress endpoint omits `totalChapters` (contract
    /// reconciliation): fill it from the cached catalog's `chapterCount` so
    /// progress rings and "x of y ch." labels stay meaningful.
    private func enrichWithChapterTotals(
        _ response: ProgressOverviewResponse
    ) -> ProgressOverviewResponse {
        guard response.progress.contains(where: { $0.totalChapters == 0 }),
              let catalog = try? loadCachedCatalog(allowStale: true)
        else { return response }
        let counts: [String: Int] = Dictionary(
            catalog.compactMap { book in book.chapterCount.map { (book.bookId, $0) } },
            uniquingKeysWith: { first, _ in first })
        let enriched = response.progress.map { item -> ProgressOverviewItem in
            guard item.totalChapters == 0, let total = counts[item.bookId] else { return item }
            return ProgressOverviewItem(
                bookId: item.bookId,
                currentChapterNumber: item.currentChapterNumber,
                totalChapters: total,
                completedChapterCount: item.completedChapterCount,
                lastReadAt: item.lastReadAt)
        }
        return ProgressOverviewResponse(progress: enriched)
    }

    // MARK: - Saved books

    public func getSaved() async throws -> [String] {
        guard reachability.isConnectedSync else { return [] }
        let response: SavedBooksResponse = try await client.send(Endpoints.getSavedBooks())
        return response.savedBookIds
    }

    public func toggleSaved(bookId: String, saved: Bool) async throws -> [String] {
        guard reachability.isConnectedSync else { throw AppError.offline }
        let endpoint = try Endpoints.toggleSaved(bookId: bookId, saved: saved)
        let response: SavedBooksResponse = try await client.send(endpoint)
        return response.savedBookIds
    }

    // MARK: - Search index

    public func getSearchIndex() async throws -> SearchIndexResponse {
        if let cached = try loadCachedSearchIndex(allowStale: true) {
            if reachability.isConnectedSync {
                Task { try? await fetchAndCacheSearchIndex() }
            }
            return cached
        }
        guard reachability.isConnectedSync else { throw AppError.offline }
        return try await fetchAndCacheSearchIndex()
    }

    private func loadCachedSearchIndex(allowStale: Bool) throws -> SearchIndexResponse? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        let key = Self.searchIndexCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        guard let record = try ctx.fetch(descriptor).first else { return nil }
        if !allowStale {
            let age = Date().timeIntervalSince(record.updatedAt)
            guard age < Self.searchIndexTTL else { return nil }
        }
        guard let data = record.value.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(SearchIndexResponse.self, from: data)
    }

    @discardableResult
    private func fetchAndCacheSearchIndex() async throws -> SearchIndexResponse {
        let response: SearchIndexResponse = try await client.send(Endpoints.getSearchIndex())
        if let container {
            try storeSearchIndex(response, in: container)
        }
        return response
    }

    private func storeSearchIndex(_ response: SearchIndexResponse, in container: ModelContainer) throws {
        let ctx = ModelContext(container)
        let key = Self.searchIndexCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        let encoded = try JSONCoding.encoder.encode(response)
        let value = String(data: encoded, encoding: .utf8) ?? ""
        if let existing = try ctx.fetch(descriptor).first {
            existing.value = value
            existing.updatedAt = Date()
        } else {
            ctx.insert(CachedKeyValue(key: key, value: value))
        }
        try ctx.save()
    }
}
