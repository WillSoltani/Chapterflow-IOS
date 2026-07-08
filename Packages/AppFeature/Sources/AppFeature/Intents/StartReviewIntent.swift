import AppIntents
import CoreKit

// MARK: - StartReviewIntent

/// "Review now" — navigates to the spaced-repetition reviews tab.
public struct StartReviewIntent: AppIntent {
    public static let title: LocalizedStringResource = "Review now"
    public static let description = IntentDescription(
        "Opens a spaced-repetition review session in ChapterFlow.",
        categoryName: "Reviews"
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run { IntentActionStore.shared.pendingDeepLink = .review }
        return .result(dialog: "Opening your review session.")
    }
}
