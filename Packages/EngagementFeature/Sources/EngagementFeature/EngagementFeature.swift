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
/// Public API added in P5.9:
/// - ``ReviewsView`` — hub: due-count hero, start session CTA, offline pending badge
/// - ``ReviewSessionView`` — full-screen session: card front → back flip → Again/Hard/Good/Easy grades
/// - ``ReviewsModel`` — `@Observable` view model; owns load and session state machines
/// - ``ReviewsRepository`` — actor data layer: `GET /book/me/reviews`, `POST /book/me/reviews/{cardId}`,
///   in-memory + SwiftData cache, offline outbox via ``PendingReviewGrade``
/// - ``ReviewNotificationScheduler`` — actor; schedules one UNCalendarNotificationTrigger per due batch
/// - ``FSRSScheduler`` — pure FSRS-5 port (19 weights); deterministic scheduling for offline use
/// - ``FSRSGrade`` — `again / hard / good / easy` with `localizedTitle` and `intervalHint`
/// - ``FSRSScheduleInput`` / ``FSRSScheduleResult`` — input/output types for the scheduler
///
/// Public API added in P5.7:
/// - ``SeasonalEventView`` — active event card with live server-time countdown, join CTA,
///   daily + total progress bars, completion banner, and empty/error states
/// - ``SeasonalEventModel`` — `@Observable` view model; maintains a 1 Hz countdown loop
///   anchored to server time (via HTTP `Date` header offset) and routes completion through
///   ``CelebrationPresenter``
/// - ``SeasonalEventRepository`` — actor-based data layer for `GET /book/events/active`,
///   `POST /book/me/events/{id}/join`, `GET|POST /book/me/events/{id}/progress`
///
/// Public API added in P5.8:
/// - ``NotebookHubView`` — unified, searchable, tag-filterable notebook + saved-books hub
/// - ``NotebookModel`` — `@Observable` view model; search/filter/edit/delete; offline-first
/// - ``SavedBooksModel`` — `@Observable` view model; saved-book IDs + catalog, offline-first
/// - ``SavedShelfView`` — three-column grid of saved books with cover + context-menu unsave
/// - ``NotebookRepository`` — actor; GET/PATCH/DELETE notebook entries; offline outbox via CachedKeyValue
///
/// Public API added in P5.10:
/// - ``CommitmentsView`` — list of active/done if-then commitments with overdue reflection CTA
/// - ``CreateCommitmentView`` — modal sheet for composing a new if-then plan with 3/7-day follow-up
/// - ``CommitmentReflectionView`` — follow-up modal: outcome selection + free-text reflection
/// - ``CommitmentsModel`` — `@Observable` view model owning load/create/reflect lifecycle
/// - ``CommitmentRepository`` — actor; GET|POST /book/me/commitments, GET|PATCH /{id};
///   schedules UNCalendarNotificationTrigger for follow-up; offline outbox via PendingCommitmentUpload
///
/// Public API added in P5.11:
/// - ``ScenariosView`` — hub: my past submissions (status + points), community inspiration
/// - ``ComposeScenarioView`` — calm modal compose UX with per-field char limits and validation
/// - ``ScenarioDetailView`` — full-screen detail: all fields, moderation status banner, points
/// - ``ScenarioRow`` — list row for a user scenario with scope tag and status badge
/// - ``ScenarioStatusBadge`` — pill badge conveying pending/approved/rejected + points
/// - ``ScenariosModel`` — `@Observable` view model; owns fetch, validation, submit lifecycle
/// - ``ScenarioRepository`` — actor; GET|POST /book/me/books/{bookId}/chapters/{n}/scenarios;
///   offline outbox via PendingScenarioUpload; syncPendingUploads() for reconnect sync
///
/// Public API added in P5.13:
/// - ``DailyGoalView`` — today's progress ring, seven-day habit week view, nudge message,
///   and goal-adjustment sheet
/// - ``DailyGoalModel`` — `@Observable` view model; loads real activity from
///   ``EngagementRepository``, reads/writes the goal via ``DailyGoalStore``
/// - ``DailyGoalStore`` — persists the user's daily goal (in minutes) to the App Group
///   `group.com.chapterflow` `UserDefaults` suite so widgets (P8.1) and reminders (P9.3)
///   can read it without depending on `EngagementFeature`
/// - ``DailyGoalState`` — immutable computed value type with `goalFraction`, `nudgeMessage`,
///   and `weekActivity`; exposed publicly for widget and reminder consumers
/// - ``DailyGoalDay`` — per-day habit indicator (date, minutesRead, fraction vs goal)
public enum EngagementFeature {
    public static let moduleName = "EngagementFeature"
}
