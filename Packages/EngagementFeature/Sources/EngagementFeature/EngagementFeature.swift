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
public enum EngagementFeature {
    public static let moduleName = "EngagementFeature"
}
