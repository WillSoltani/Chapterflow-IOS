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
    static let badges = "engagement.badges"
    static let flowPoints = "engagement.flowPoints"
    static let shop = "engagement.shop"
    static let tier = "engagement.tier"
}

// MARK: - EngagementRepository

/// The single read path for all engagement data: dashboard, streak, flow-points, tier, badges, and shop.
///
/// P5.2–P5.13 depend on this actor to access the endpoints it aggregates:
/// - `GET /book/me/dashboard`
/// - `GET /book/me/streak`
/// - `GET /book/me/progress`
/// - `GET /book/me/badges`
/// - `GET /book/me/flow-points` (P5.4 — balance, ledger, equipped cosmetics)
/// - `GET /book/me/shop` (P5.4 — rewards and cosmetics catalogue)
/// - `POST /book/me/flow-points/redeem` (P5.4 — buy/equip)
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
    private var memBadges: MemEntry<[BadgeItem]>?
    private var memFlowPoints: MemEntry<FlowPointsResponse>?
    private var memShop: MemEntry<ShopResponse>?
    private var memTier: MemEntry<TierState>?

    // TTLs
    private let dashboardTTL: TimeInterval = 5 * 60
    private let streakTTL: TimeInterval = 10 * 60
    private let progressTTL: TimeInterval = 5 * 60
    private let badgesTTL: TimeInterval = 10 * 60
    private let flowPointsTTL: TimeInterval = 2 * 60
    private let shopTTL: TimeInterval = 5 * 60
    private let tierTTL: TimeInterval = 5 * 60

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

    // MARK: - Public: Badges

    public func fetchBadges(forceRefresh: Bool = false) async throws -> [BadgeItem] {
        if !forceRefresh, let entry = memBadges, !entry.isStale(ttl: badgesTTL) {
            return entry.value
        }
        do {
            let resp: BadgesResponse = try await apiClient.send(Endpoints.getBadges())
            let value = resp.badges
            memBadges = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: CacheKey.badges, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: BadgesResponse = loadFromDisk(key: CacheKey.badges) {
                memBadges = MemEntry(value: cached.badges, storedAt: Date())
                return cached.badges
            }
            if let entry = memBadges { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Public: Flow Points

    /// Fetches the detailed flow-points state: balance, transaction ledger, and equipped cosmetics.
    ///
    /// Uses a 2-minute in-memory TTL; falls back to disk cache when offline.
    public func fetchFlowPoints(forceRefresh: Bool = false) async throws -> FlowPointsResponse {
        if !forceRefresh, let entry = memFlowPoints, !entry.isStale(ttl: flowPointsTTL) {
            return entry.value
        }
        do {
            let resp: FlowPointsResponse = try await apiClient.send(Endpoints.getFlowPoints())
            memFlowPoints = MemEntry(value: resp, storedAt: Date())
            persistToDisk(key: CacheKey.flowPoints, encodable: resp)
            return resp
        } catch AppError.offline {
            if let cached: FlowPointsResponse = loadFromDisk(key: CacheKey.flowPoints) {
                memFlowPoints = MemEntry(value: cached, storedAt: Date())
                return cached
            }
            if let entry = memFlowPoints { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Public: Shop

    /// Fetches the shop catalogue of rewards and cosmetics.
    ///
    /// Uses a 5-minute in-memory TTL; falls back to disk cache when offline.
    public func fetchShop(forceRefresh: Bool = false) async throws -> ShopResponse {
        if !forceRefresh, let entry = memShop, !entry.isStale(ttl: shopTTL) {
            return entry.value
        }
        do {
            let resp: ShopResponse = try await apiClient.send(Endpoints.getShop())
            memShop = MemEntry(value: resp, storedAt: Date())
            persistToDisk(key: CacheKey.shop, encodable: resp)
            return resp
        } catch AppError.offline {
            if let cached: ShopResponse = loadFromDisk(key: CacheKey.shop) {
                memShop = MemEntry(value: cached, storedAt: Date())
                return cached
            }
            if let entry = memShop { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Public: Tier

    /// Fetches the user's current tier state from `POST /book/me/tier`.
    ///
    /// The server evaluates the user's metrics and returns the full tier breakdown.
    /// When `recentlyPromoted` is `true` in the response, the caller should fire
    /// a `.tierUp` celebration through `CelebrationPresenter`.
    ///
    /// Results are cached for 5 minutes; force-refresh to pick up promotion events.
    public func fetchTier(forceRefresh: Bool = false) async throws -> TierState {
        if !forceRefresh, let entry = memTier, !entry.isStale(ttl: tierTTL) {
            return entry.value
        }
        do {
            let endpoint = try Endpoints.postTier()
            let resp: TierResponse = try await apiClient.send(endpoint)
            let value = resp.tier
            memTier = MemEntry(value: value, storedAt: Date())
            persistToDisk(key: CacheKey.tier, encodable: resp)
            return value
        } catch AppError.offline {
            if let cached: TierResponse = loadFromDisk(key: CacheKey.tier) {
                memTier = MemEntry(value: cached.tier, storedAt: Date())
                return cached.tier
            }
            if let entry = memTier { return entry.value }
            throw AppError.offline
        }
    }

    // MARK: - Public: Redeem

    /// Redeems a shop item (buy or equip).
    ///
    /// - Parameters:
    ///   - itemId: The shop item to act on.
    ///   - action: `nil` = buy (costs flow points); `"equip"` = activate an
    ///     already-owned cosmetic (no cost). The server is authoritative.
    ///
    /// On success, both the flow-points and shop caches are invalidated so the
    /// next fetch reflects the server's updated state.
    public func redeemItem(itemId: String, action: String?) async throws -> RedeemFlowPointsResponse {
        let endpoint = try Endpoints.redeemFlowPoints(itemId: itemId, action: action)
        let response: RedeemFlowPointsResponse = try await apiClient.send(endpoint)
        // Invalidate caches so the next fetch gets fresh ownership + balance data.
        memFlowPoints = nil
        memShop = nil
        return response
    }

    // MARK: - Public: Accessors derived from last-known state

    public var currentDashboard: Dashboard? { memDashboard?.value }
    public var currentStreak: StreakState? { memStreak?.value }
    public var currentProgress: [ProgressOverviewItem]? { memProgress?.value }
    public var currentBadges: [BadgeItem]? { memBadges?.value }

    public var flowPointsBalance: Int? { memDashboard?.value.flowPoints }
    public var tier: String? { memDashboard?.value.tier }
    public var tierProgress: Double? { memDashboard?.value.tierProgress }

    /// The cosmetics currently equipped by the user, from the most recent flow-points fetch.
    ///
    /// `nil` before the first successful `fetchFlowPoints` call.
    /// Profile and Reader features read this to apply active themes and frames.
    public var currentEquippedCosmetics: EquippedCosmetics? { memFlowPoints?.value.equippedCosmetics }

    // MARK: - Loop-completion refresh

    /// Force-refreshes streak, dashboard, and progress after a quiz pass.
    ///
    /// The server updates these values server-side as part of the quiz-pass pipeline;
    /// this call pulls the fresh state so the UI reflects the new streak, flow-points,
    /// and tier immediately after the loop-completion celebration.
    ///
    /// Returns the refreshed snapshot, or throws if the network is unavailable and
    /// no cached data exists.
    public func refreshAfterLoopComplete() async throws -> DashboardSnapshot {
        return try await fetchDashboardSnapshot(forceRefresh: true)
    }

    // MARK: - Cache invalidation

    public func invalidateAll() {
        memDashboard = nil
        memStreak = nil
        memProgress = nil
        memBadges = nil
        memFlowPoints = nil
        memShop = nil
        memTier = nil
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
