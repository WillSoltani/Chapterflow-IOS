import EngagementFeature
import Foundation
import SettingsFeature

/// Feature models whose state belongs to one authenticated session scope.
///
/// The composition root creates exactly one owner for each active scope. Views
/// borrow these models; they never construct account-owned state while rendering.
@MainActor
final class SessionFeatureModels {
    let scopeID: UUID
    let reviews: ReviewsModel
    let settings: SettingsModel

    init(
        scopeID: UUID,
        graph: SessionPrivateGraph,
        onSignOut: @escaping () async -> Void
    ) {
        precondition(scopeID == graph.context.instanceID)
        self.scopeID = scopeID
        reviews = ReviewsModel(
            repository: graph.reviewsRepository,
            workPermit: graph.permit,
            analytics: graph.analytics
        )
        settings = SettingsModel(
            repository: graph.settingsRepository,
            preferences: graph.preferences,
            onSignOut: onSignOut,
            downloadInfoProvider: graph.downloadManager,
            accountContext: graph.context,
            workPermit: graph.permit
        )
    }

    init(
        scopeID: UUID,
        reviews: ReviewsModel,
        settings: SettingsModel
    ) {
        self.scopeID = scopeID
        self.reviews = reviews
        self.settings = settings
    }
}
