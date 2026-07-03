import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "journeys")

private enum JourneysCacheKey {
    static let catalog = "journeys.catalog"
}

// MARK: - JourneysRepository

/// Data layer for curated multi-book journey paths.
///
/// - `GET /book/books/journeys` — catalog of available journeys (cached, longer TTL)
/// - `GET /book/me/journeys/{id}` — user's enrollment + progress (short TTL)
/// - `POST /book/me/journeys/{id}/start` — enroll/start a journey
public actor JourneysRepository {

    // MARK: Dependencies

    private let apiClient: any APIClientProtocol
    private let modelContainer: ModelContainer?

    // MARK: In-memory layer

    private struct MemEntry<T: Sendable> {
        let value: T
        let storedAt: Date
        func isStale(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(storedAt) >= ttl
        }
    }

    private var memCatalog: MemEntry<[JourneyCatalogItem]>?
    private var memUserJourneys: [String: MemEntry<UserJourney>] = [:]

    private let catalogTTL: TimeInterval = 15 * 60
    private let userJourneyTTL: TimeInterval = 2 * 60

    // MARK: Init

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    /// Fetches the list of all available journey paths.
    public func fetchJourneys(forceRefresh: Bool = false) async throws -> [JourneyCatalogItem] {
        if !forceRefresh, let entry = memCatalog, !entry.isStale(ttl: catalogTTL) {
            return entry.value
        }
        do {
            let resp: JourneysListResponse = try await apiClient.send(Endpoints.getJourneys())
            let value = resp.journeys
            memCatalog = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: JourneysCacheKey.catalog, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: JourneysListResponse = loadFromDisk(key: JourneysCacheKey.catalog) {
                let value = cached.journeys
                memCatalog = MemEntry(value: value, storedAt: Date())
                return value
            }
            if let entry = memCatalog { return entry.value }
            throw AppError.offline
        }
    }

    /// Fetches the current user's progress on a specific journey.
    public func fetchUserJourney(id: String, forceRefresh: Bool = false) async throws -> UserJourney {
        if !forceRefresh, let entry = memUserJourneys[id], !entry.isStale(ttl: userJourneyTTL) {
            return entry.value
        }
        do {
            let resp: UserJourneyResponse = try await apiClient.send(Endpoints.getUserJourney(id: id))
            let value = resp.journey
            memUserJourneys[id] = MemEntry(value: value, storedAt: Date())
            return value
        } catch AppError.offline {
            if let entry = memUserJourneys[id] { return entry.value }
            throw AppError.offline
        }
    }

    /// Enrolls the user in a journey (or no-ops if already enrolled) and returns their progress.
    public func startJourney(id: String) async throws -> UserJourney {
        let endpoint = try Endpoints.startJourney(id: id)
        let resp: UserJourneyResponse = try await apiClient.send(endpoint)
        let value = resp.journey
        memUserJourneys[id] = MemEntry(value: value, storedAt: Date())
        return value
    }

    // MARK: - Cache invalidation

    public func invalidate() {
        memCatalog = nil
        memUserJourneys.removeAll()
    }

    // MARK: - Disk helpers

    private func persistToDisk<T: Encodable>(key: String, encodable: T) {
        guard let container = modelContainer else { return }
        guard let data = try? JSONCoding.encoder.encode(encodable),
              let json = String(data: data, encoding: .utf8) else { return }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.value = json
            existing.updatedAt = Date()
        } else {
            context.insert(CachedKeyValue(key: key, value: json))
        }
        do {
            try context.save()
        } catch {
            log.warning("Journey cache write failed for key '\(key)': \(error)")
        }
    }

    private func loadFromDisk<T: Decodable>(key: String) -> T? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CachedKeyValue>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        guard let data = entry.value.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: data)
    }
}
