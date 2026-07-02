import Foundation
import CoreKit
import Models
import Networking
import Persistence
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.chapterflow.engagement", category: "repository")

// MARK: - Cache keys

private enum CacheKey {
    static let dashboard = "engagement.dashboard"
    static let streak = "engagement.streak"
    static let progress = "engagement.progress"
}

// MARK: - EngagementRepository

/// The single read path for all engagement data: dashboard, streak, flow-points, and tier.
///
/// P5.2–P5.13 depend on this actor to access the three endpoints it aggregates:
/// - `GET /book/me/dashboard`
/// - `GET /book/me/streak`
/// - `GET /book/me/progress`
///
/// ### Cache strategy
/// Every fetch checks an in-memory store first (fast, session-scoped), then a
/// `CachedKeyValue` row in SwiftData (durable, survives restarts). Stale in-memory
/// entries fall back to disk. When the network is unavailable the cached value is
/// returned; callers receive an `AppError.offline` only when no cache exists.
public actor EngagementRepository {

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

    private var memDashboard: MemEntry<Dashboard>?
    private var memStreak: MemEntry<StreakState>?
    private var memProgress: MemEntry<[ProgressOverviewItem]>?

    // TTLs
    private let dashboardTTL: TimeInterval = 5 * 60
    private let streakTTL: TimeInterval = 10 * 60
    private let progressTTL: TimeInterval = 5 * 60

    // MARK: Init

    public init(apiClient: some APIClientProtocol, modelContainer: ModelContainer? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
    }

    // MARK: - Public: Aggregate fetch

    /// Fetches all three engagement resources in parallel.
    ///
    /// Uses cached values when available unless `forceRefresh` is `true`.
    /// Falls back to on-disk cache when the network is unavailable.
    public func fetchDashboardSnapshot(forceRefresh: Bool = false) async throws -> DashboardSnapshot {
        async let d = fetchDashboard(forceRefresh: forceRefresh)
        async let s = fetchStreak(forceRefresh: forceRefresh)
        async let p = fetchProgress(forceRefresh: forceRefresh)
        return try await DashboardSnapshot(dashboard: d, streak: s, progress: p)
    }

    // MARK: - Public: Individual fetches

    public func fetchDashboard(forceRefresh: Bool = false) async throws -> Dashboard {
        if !forceRefresh, let entry = memDashboard, !entry.isStale(ttl: dashboardTTL) {
            return entry.value
        }
        do {
            let resp: DashboardResponse = try await apiClient.send(Endpoints.getDashboard())
            let value = resp.dashboard
            memDashboard = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: CacheKey.dashboard, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: DashboardResponse = loadFromDisk(key: CacheKey.dashboard) {
                memDashboard = MemEntry(value: cached.dashboard, storedAt: Date())
                return cached.dashboard
            }
            if let entry = memDashboard { return entry.value }
            throw AppError.offline
        }
    }

    public func fetchStreak(forceRefresh: Bool = false) async throws -> StreakState {
        if !forceRefresh, let entry = memStreak, !entry.isStale(ttl: streakTTL) {
            return entry.value
        }
        do {
            let resp: StreakResponse = try await apiClient.send(Endpoints.getStreak())
            let value = resp.streak
            memStreak = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: CacheKey.streak, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: StreakResponse = loadFromDisk(key: CacheKey.streak) {
                memStreak = MemEntry(value: cached.streak, storedAt: Date())
                return cached.streak
            }
            if let entry = memStreak { return entry.value }
            throw AppError.offline
        }
    }

    public func fetchProgress(forceRefresh: Bool = false) async throws -> [ProgressOverviewItem] {
        if !forceRefresh, let entry = memProgress, !entry.isStale(ttl: progressTTL) {
            return entry.value
        }
        do {
            let resp: ProgressOverviewResponse = try await apiClient.send(Endpoints.getProgressOverview())
            let value = resp.progress
            memProgress = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: CacheKey.progress, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: ProgressOverviewResponse = loadFromDisk(key: CacheKey.progress) {
                memProgress = MemEntry(value: cached.progress, storedAt: Date())
                return cached.progress
            }
            if let entry = memProgress { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Public: Accessors derived from last-known state

    public var currentDashboard: Dashboard? { memDashboard?.value }
    public var currentStreak: StreakState? { memStreak?.value }
    public var currentProgress: [ProgressOverviewItem]? { memProgress?.value }

    public var flowPointsBalance: Int? { memDashboard?.value.flowPoints }
    public var tier: String? { memDashboard?.value.tier }
    public var tierProgress: Double? { memDashboard?.value.tierProgress }

    // MARK: - Cache invalidation

    public func invalidateAll() {
        memDashboard = nil
        memStreak = nil
        memProgress = nil
    }

    // MARK: - Disk cache helpers (run on actor executor)

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
            log.warning("Engagement cache write failed for key '\(key)': \(error)")
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
