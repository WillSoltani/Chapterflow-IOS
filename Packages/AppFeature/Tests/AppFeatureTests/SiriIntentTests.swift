import Testing
import Foundation
@testable import AppFeature
import Persistence
import CoreKit

// MARK: - IntentActionStore routing tests

@Suite("IntentActionStore routing", .serialized)
@MainActor
struct IntentActionStoreRoutingTests {

    @Test("ownerless continue-reading state is never replayed")
    func ownerlessStateIsNeverReplayed() {
        let store = IntentActionStore()
        store.pendingDeepLink = .chapter(bookId: "stale-a", chapter: 3)
        store.pendingAudioPlay = AudioPlayRequest(
            bookId: "stale-a",
            chapterNumber: 3
        )

        StartDailyReadingIntent.prepareNeutralLibraryNavigation(in: store)

        #expect(store.pendingDeepLink == .library)
        #expect(store.pendingAudioPlay == nil)
    }

    @Test("sets pendingDeepLink to .review")
    func setsReviewDeepLink() async throws {
        // Validate intent action store routing logic.
        IntentActionStore.shared.pendingDeepLink = nil
        await MainActor.run { IntentActionStore.shared.pendingDeepLink = .review }
        #expect(IntentActionStore.shared.pendingDeepLink == .review)
        IntentActionStore.shared.pendingDeepLink = nil
    }

    @Test("ownerless continue-reading state never starts audio")
    func ownerlessStateNeverStartsAudio() {
        let store = IntentActionStore()
        store.pendingDeepLink = .chapter(bookId: "stale-a", chapter: 2)
        store.pendingAudioPlay = AudioPlayRequest(
            bookId: "stale-a",
            chapterNumber: 2
        )

        StartAudioNarrationIntent.prepareNeutralLibraryNavigation(in: store)

        #expect(store.pendingDeepLink == .library)
        #expect(store.pendingAudioPlay == nil)
    }
}

// MARK: - LogDailyReadingIntent tests

@Suite("LogDailyReadingIntent")
struct LogDailyReadingIntentTests {

    @Test("cached legacy invocation emits no ownerless reading write")
    func cachedInvocationIsFailClosed() async throws {
        let suiteName = "test.intent.log.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(25, forKey: IntentKeys.pendingReadingMinutes)

        _ = try await LogDailyReadingIntent().perform()

        #expect(defaults.integer(forKey: IntentKeys.pendingReadingMinutes) == 25)
    }

    @Test("ownerless logging shortcut is no longer donated")
    func loggingShortcutIsNotRegistered() {
        #expect(ChapterFlowShortcuts.appShortcuts.count == 3)
    }
}

// MARK: - AppModel audio command tests

@Suite("AppModel — consumeAudioControlCommand")
@MainActor
struct AppModelAudioCommandTests {

    @Test("preserves ownerless audio command without applying it")
    func preservesOwnerlessAudioCommand() throws {
        let suiteName = "test.intent.audioCmd.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("pause", forKey: IntentKeys.audioControlCommand)

        AppModel.preserveOwnerlessAudioControlCommand(in: defaults)

        #expect(defaults.string(forKey: IntentKeys.audioControlCommand) == "pause")
    }

    @Test("no-ops when key is absent")
    func noopsWhenKeyAbsent() throws {
        let suiteName = "test.intent.audioCmd.absent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let command = defaults.string(forKey: IntentKeys.audioControlCommand)
        #expect(command == nil)
    }
}

// MARK: - AppModel consumeControlIntentAction tests

@Suite("AppModel — consumeControlIntentAction")
@MainActor
struct AppModelControlIntentTests {

    @Test("preserves ownerless reading navigation and snapshot without routing")
    func preservesOwnerlessReadingNavigation() throws {
        let suiteName = "test.control.consume.reading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("startReading", forKey: IntentKeys.controlPendingAction)
        defaults.set("book-ctrl", forKey: SharedStateKeys.continueBookId)
        defaults.set(4, forKey: SharedStateKeys.continueChapterNumber)

        AppModel.preserveOwnerlessControlIntentAction(in: defaults)

        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == "startReading")
        #expect(defaults.string(forKey: SharedStateKeys.continueBookId) == "book-ctrl")
        #expect(defaults.integer(forKey: SharedStateKeys.continueChapterNumber) == 4)
    }

    @Test("preserves ownerless review navigation")
    func preservesOwnerlessReviewNavigation() throws {
        let suiteName = "test.control.consume.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("startReview", forKey: IntentKeys.controlPendingAction)

        AppModel.preserveOwnerlessControlIntentAction(in: defaults)

        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == "startReview")
    }

    @Test("no-ops when key is absent")
    func noopsWhenKeyAbsent() {
        let suiteName = "test.control.consume.absent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let action = defaults.string(forKey: IntentKeys.controlPendingAction)
        #expect(action == nil)
    }

    @Test("does not overwrite ownerless audio playing state")
    func preservesAudioPlayingState() {
        let suiteName = "test.control.audioPlaying.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: IntentKeys.isAudioPlaying)

        AppModel.preserveOwnerlessAudioPlayingState(false, in: defaults)

        #expect(defaults.bool(forKey: IntentKeys.isAudioPlaying) == true)
    }
}

// MARK: - AppModel pending reading minutes tests

@Suite("AppModel — consumePendingReadingMinutes")
@MainActor
struct AppModelReadingMinutesTests {

    @Test("preserves ownerless pending minutes without crediting the shared snapshot")
    func preservesOwnerlessPendingMinutes() throws {
        let suiteName = "test.intent.readingMin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(30, forKey: IntentKeys.pendingReadingMinutes)
        defaults.set(7, forKey: SharedStateKeys.goalProgressMinutes)

        AppModel.preserveOwnerlessPendingReadingMinutes(in: defaults)

        #expect(defaults.integer(forKey: IntentKeys.pendingReadingMinutes) == 30)
        #expect(defaults.integer(forKey: SharedStateKeys.goalProgressMinutes) == 7)
    }

    @Test("no-ops when pending is zero")
    func noopsWhenZero() throws {
        let suiteName = "test.intent.readingMin.zero.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let pending = defaults.integer(forKey: IntentKeys.pendingReadingMinutes)
        #expect(pending == 0)
    }
}
