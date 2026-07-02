/// EngagementFeature — progress dashboard, streak, flow-points, tier, badges, reviews, journeys.
///
/// Public API surface for P5.1:
/// - ``EngagementRepository`` — shared data layer (dashboard/streak/progress/points/tier)
/// - ``DashboardView`` — SwiftUI progress dashboard with Swift Charts
/// - ``DashboardModel`` — `@Observable` view model for the dashboard
/// - ``DashboardSnapshot`` — immutable aggregate of the three engagement endpoints
public enum EngagementFeature {
    public static let moduleName = "EngagementFeature"
}
