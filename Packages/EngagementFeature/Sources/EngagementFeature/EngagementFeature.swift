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
public enum EngagementFeature {
    public static let moduleName = "EngagementFeature"
}
