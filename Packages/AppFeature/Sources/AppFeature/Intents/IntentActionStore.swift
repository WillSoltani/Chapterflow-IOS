import SwiftUI
import CoreKit

// MARK: - AudioPlayRequest

/// Parameters needed to start audio narration from an App Intent.
public struct AudioPlayRequest: Sendable, Equatable {
    public let bookId: String
    public let chapterNumber: Int

    public init(bookId: String, chapterNumber: Int) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
    }
}

// MARK: - IntentActionStore

/// Singleton @Observable store that App Intents write into and AppRootView reads.
///
/// Intent `perform()` methods hop onto @MainActor via `await MainActor.run { }`
/// to mutate this store. AppRootView observes the properties via `.onChange(of:)`.
///
/// Only `openAppWhenRun: true` intents use this store — they run in the main app
/// process so the store is reachable. Inline intents use App Group UserDefaults
/// instead (see ``IntentKeys``).
@Observable
@MainActor
public final class IntentActionStore {
    public static let shared = IntentActionStore()
    private init() {}

    /// A deep link to navigate to. Cleared by AppRootView after routing.
    public var pendingDeepLink: DeepLink?

    /// Start audio at this book/chapter. Cleared by AppRootView after dispatch.
    public var pendingAudioPlay: AudioPlayRequest?
}
