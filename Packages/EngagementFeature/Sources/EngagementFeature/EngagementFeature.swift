/// EngagementFeature — progress dashboard, streak, flow-points, tier, badges, reviews, journeys.
///
/// Public API surface for P5.1:
/// - ``EngagementRepository`` — shared data layer (dashboard/streak/progress/points/tier)
/// - ``DashboardView`` — SwiftUI progress dashboard with Swift Charts
/// - ``DashboardModel`` — `@Observable` view model for the dashboard
/// - ``DashboardSnapshot`` — immutable aggregate of the three engagement endpoints
///
/// Public API added in P5.12:
/// - ``CelebrationEvent`` — typed reward moments features enqueue
/// - ``CelebrationPresenter`` — single source of truth; serialises a queue into one sequence
/// - ``CelebrationView`` — full-screen overlay; mount once at a feature root
///
/// Public API added in P5.2:
/// - ``StreakView`` — 30-day heatmap, shields, milestone ladder, at-risk banner
/// - ``StreakModel`` — `@Observable` view model; fires one-per-day streak celebrations
/// - ``HeatmapDay`` — a single day entry for the heatmap grid
///
/// Public API added in P5.3:
/// - ``BadgesView`` — earned/locked badge grid with track filtering
/// - ``BadgesModel`` — `@Observable` view model; detects newly earned badges and routes them
///   through ``CelebrationPresenter``
/// - ``AchievementTrack`` — display enum for the four badge tracks (mastery/consistency/exploration/hidden)
///
/// Public API added in P5.4:
/// - ``FlowPointsView`` — balance hero, transaction ledger, and shop with buy/equip
/// - ``FlowPointsModel`` — `@Observable` view model for the economy screen
/// - ``ShopItemAction`` — action enum driving shop item buttons (buy/equip/owned/equipped)
/// - ``EngagementRepository.fetchFlowPoints(forceRefresh:)`` — balance + ledger + equipped cosmetics
/// - ``EngagementRepository.fetchShop(forceRefresh:)`` — shop catalogue
/// - ``EngagementRepository.redeemItem(itemId:action:)`` — buy or equip (server-authoritative)
/// - ``EngagementRepository.currentEquippedCosmetics`` — active theme/frame for Profile and Reader
///
/// Public API added in P5.5:
/// - ``TierView`` — current tier, per-metric progress (loops/score/categories), tier-ladder mini-map
/// - ``TierModel`` — `@Observable` view model; fires a one-per-tier `.tierUp` celebration
/// - ``EngagementRepository.fetchTier(forceRefresh:)`` — detailed tier state from `POST /book/me/tier`
///
/// Public API added in P5.6:
/// - ``JourneysListView`` — list of all available curated multi-book paths with gradient covers
/// - ``JourneyDetailView`` — ordered book sequence, user progress, and Start/Continue action
/// - ``JourneysModel`` — `@Observable` view model for the journey catalog
/// - ``JourneyDetailModel`` — `@Observable` view model for a single journey's progress
/// - ``JourneysRepository`` — data layer for `GET /book/books/journeys`,
///   `GET /book/me/journeys/{id}`, `POST /book/me/journeys/{id}/start`
///
/// Public API added in P5.7:
/// - ``SeasonalEventView`` — active event card with live server-time countdown, join CTA,
///   daily + total progress bars, completion banner, and empty/error states
/// - ``SeasonalEventModel`` — `@Observable` view model; maintains a 1 Hz countdown loop
///   anchored to server time (via HTTP `Date` header offset) and routes completion through
///   ``CelebrationPresenter``
/// - ``SeasonalEventRepository`` — actor-based data layer for `GET /book/events/active`,
///   `POST /book/me/events/{id}/join`, `GET|POST /book/me/events/{id}/progress`
public enum EngagementFeature {
    public static let moduleName = "EngagementFeature"
}
