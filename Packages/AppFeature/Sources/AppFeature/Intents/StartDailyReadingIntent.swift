import AppIntents
import CoreKit
import Persistence

// MARK: - StartDailyReadingIntent

/// "Start my daily reading" — opens the reader at the user's last position.
///
/// Reads the App Group snapshot so the intent works without launching the app first.
/// On activation the app routes to the chapter via ``IntentActionStore``.
public struct StartDailyReadingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start my daily reading"
    public static let description = IntentDescription(
        "Opens ChapterFlow at the chapter you left off.",
        categoryName: "Reading"
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        let snapshot = SharedStateReader().load()
        let link: DeepLink
        if let bookId = snapshot.continueBookId, let chapter = snapshot.continueChapterNumber {
            link = .chapter(bookId: bookId, chapter: chapter)
        } else {
            link = .library
        }
        await MainActor.run { IntentActionStore.shared.pendingDeepLink = link }
        let title = snapshot.continueBookTitle ?? "your library"
        return .result(dialog: "Opening \(title).")
    }
}
