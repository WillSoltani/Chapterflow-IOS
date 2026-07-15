import AppIntents
import CoreKit

// MARK: - StartAudioNarrationIntent

/// Opens ChapterFlow's library so the user can choose audio in-app.
///
/// Continue-reading snapshots in the App Group are ownerless legacy state. Until
/// WP-ID-01B binds that state to an account, this intent deliberately opens the
/// neutral library and never turns that snapshot into an audio request.
///
public struct StartAudioNarrationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Browse audio in ChapterFlow"
    public static let description = IntentDescription(
        "Opens your library so you can choose a book to listen to.",
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
        return .result(dialog: "Opening your library. Select a book to listen to.")
    }
}
