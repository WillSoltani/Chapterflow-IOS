import Foundation
import SwiftData
import Models
import Networking
import Persistence

/// Production ``LibraryRepository`` that fetches from the ChapterFlow REST API
/// and caches the catalog in a SwiftData `CachedKeyValue` store (5-minute TTL).
public actor LiveLibraryRepository: LibraryRepository {

    private let client: any APIClientProtocol
    private let container: ModelContainer?

    private static let catalogCacheKey = "library.catalog.v1"
    private static let searchIndexCacheKey = "library.searchIndex.v1"
    private static let cacheTTL: TimeInterval = 300
    private static let searchIndexTTL: TimeInterval = 1800 // 30 min — heavier payload

    public init(client: any APIClientProtocol, container: ModelContainer? = nil) {
        self.client = client
        self.container = container
    }

    // MARK: - Catalog

    public func getCatalog() async throws -> [BookCatalogItem] {
        if let cached = try loadCachedCatalog() { return cached }
        return try await fetchAndCacheCatalog()
    }

    private func loadCachedCatalog() throws -> [BookCatalogItem]? {
        guard let container else { return nil }
        let ctx = ModelContext(container)
        let key = Self.catalogCacheKey
        let descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        guard let record = try ctx.fetch(descriptor).first else { return nil }
        let age = Date().timeIntervalSince(record.updatedAt)
        guard age < Self.cacheTTL else { return nil }
        guard let data = record.value.data(using: .utf8) else { return nil }
        return try JSONCoding.decoder.decode(CatalogResponse.self, from: data).books
    }

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
        try await client.send(Endpoints.getProgressOverview())
    }

    // MARK: - Saved books

    public func getSaved() async throws -> [String] {
        let response: SavedBooksResponse = try await client.send(Endpoints.getSavedBooks())
        return response.savedBookIds
    }

    public func toggleSaved(bookId: String, saved: Bool) async throws -> [String] {
        let endpoint = try Endpoints.toggleSaved(bookId: bookId, saved: saved)
        let response: SavedBooksResponse = try await client.send(endpoint)
        return response.savedBookIds
    }

    // MARK: - Search index

    public func getSearchIndex() async throws -> SearchIndexResponse {
        // Try stale-while-revalidate: return cached data immediately if present
        // (even if expired), then refresh in background. If no cache at all,
        // fetch synchronously so the caller gets real data.
        if let cached = try loadCachedSearchIndex(allowStale: false) {
            return cached
        }
        // Check for stale cache — serve it while hiding the network error.
        if let stale = try loadCachedSearchIndex(allowStale: true) {
            Task { try? await fetchAndCacheSearchIndex() }
            return stale
        }
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
