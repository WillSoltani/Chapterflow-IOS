import AppIntents
import CoreKit
import Persistence

// MARK: - StartAudioNarrationIntent

/// "Read with ChapterFlow" — starts audio narration of the current chapter.
///
/// Reads the App Group snapshot for the continue-reading context, then signals
/// ``IntentActionStore`` which AppRootView observes to start ``AudioPlayerModel``.
///
/// Audio control (pause/resume) during playback is handled by the P8.2
/// ``PauseAudioIntent`` / ``ResumeAudioIntent`` Live Activity buttons.
public struct StartAudioNarrationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Read with ChapterFlow"
    public static let description = IntentDescription(
        "Starts audio narration of your current chapter.",
        categoryName: "Reading"
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        let snapshot = SharedStateReader().load()
        guard let bookId = snapshot.continueBookId,
              let chapter = snapshot.continueChapterNumber else {
            await MainActor.run { IntentActionStore.shared.pendingDeepLink = .library }
            return .result(dialog: "Opening your library. Select a book to listen to.")
        }
        let request = AudioPlayRequest(bookId: bookId, chapterNumber: chapter)
        await MainActor.run { IntentActionStore.shared.pendingAudioPlay = request }
        let title = snapshot.continueBookTitle ?? "your current chapter"
        return .result(dialog: "Starting narration of \(title).")
    }
}
