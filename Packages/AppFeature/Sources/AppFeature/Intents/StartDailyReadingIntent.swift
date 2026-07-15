import AppIntents
import CoreKit

// MARK: - StartDailyReadingIntent

/// Opens ChapterFlow at a neutral library destination.
///
/// Continue-reading snapshots in the App Group are ownerless legacy state. Until
/// WP-ID-01B binds that state to an account, this intent deliberately opens the
/// neutral library instead of replaying one account's book into another scope.
public struct StartDailyReadingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open my ChapterFlow library"
    public static let description = IntentDescription(
        "Opens your ChapterFlow library without using an unverified reading position.",
        categoryName: "Reading"
    )
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    static func prepareNeutralLibraryNavigation(in store: IntentActionStore) {
        store.pendingAudioPlay = nil
        store.pendingDeepLink = .library
    }

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            Self.prepareNeutralLibraryNavigation(in: .shared)
        }
        return .result(dialog: "Opening your library.")
    }
}
