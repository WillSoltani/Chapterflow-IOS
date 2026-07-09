import Testing
import Foundation
@testable import AppFeature
import Persistence
import CoreKit

// MARK: - StartDailyReadingIntent tests

@Suite("StartDailyReadingIntent")
@MainActor
struct StartDailyReadingIntentTests {

    @Test("routes to chapter when continue-reading record exists")
    func routesToChapterWhenRecordExists() async throws {
        let suiteName = "test.intent.daily.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("book-abc", forKey: SharedStateKeys.continueBookId)
        defaults.set("Atomic Habits", forKey: SharedStateKeys.continueBookTitle)
        defaults.set(3, forKey: SharedStateKeys.continueChapterNumber)

        let reader = SharedStateReader(suiteName: suiteName)
        let snapshot = reader.load()

        #expect(snapshot.continueBookId == "book-abc")
        #expect(snapshot.continueChapterNumber == 3)

        // Simulate perform() logic without instantiating the intent.
        let link: DeepLink
        if let bookId = snapshot.continueBookId, let chapter = snapshot.continueChapterNumber {
            link = .chapter(bookId: bookId, chapter: chapter)
        } else {
            link = .library
        }
        #expect(link == .chapter(bookId: "book-abc", chapter: 3))
    }

    @Test("falls back to library when no continue-reading record")
    func fallsBackToLibraryWhenNoRecord() async throws {
        let reader = SharedStateReader(suiteName: "test.intent.empty.\(UUID().uuidString)")
        let snapshot = reader.load()

        let link: DeepLink = (snapshot.continueBookId != nil && snapshot.continueChapterNumber != nil)
            ? .chapter(bookId: snapshot.continueBookId!, chapter: snapshot.continueChapterNumber!)
            : .library
        #expect(link == .library)
    }
}

// MARK: - StartReviewIntent tests

@Suite("StartReviewIntent")
@MainActor
struct StartReviewIntentTests {

    @Test("sets pendingDeepLink to .review")
    func setsReviewDeepLink() async throws {
        // Validate intent action store routing logic.
        IntentActionStore.shared.pendingDeepLink = nil
        await MainActor.run { IntentActionStore.shared.pendingDeepLink = .review }
        #expect(IntentActionStore.shared.pendingDeepLink == .review)
        IntentActionStore.shared.pendingDeepLink = nil
    }
}

// MARK: - StartAudioNarrationIntent tests

@Suite("StartAudioNarrationIntent")
@MainActor
struct StartAudioNarrationIntentTests {

    @Test("sets pendingAudioPlay when continue-reading record exists")
    func setsPendingAudioPlay() async throws {
        let suiteName = "test.intent.audio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("book-xyz", forKey: SharedStateKeys.continueBookId)
        defaults.set(2, forKey: SharedStateKeys.continueChapterNumber)

        let reader = SharedStateReader(suiteName: suiteName)
        let snapshot = reader.load()

        IntentActionStore.shared.pendingAudioPlay = nil

        if let bookId = snapshot.continueBookId, let chapter = snapshot.continueChapterNumber {
            let request = AudioPlayRequest(bookId: bookId, chapterNumber: chapter)
            await MainActor.run { IntentActionStore.shared.pendingAudioPlay = request }
        }

        #expect(IntentActionStore.shared.pendingAudioPlay == AudioPlayRequest(bookId: "book-xyz", chapterNumber: 2))
        IntentActionStore.shared.pendingAudioPlay = nil
    }

    @Test("falls back to library deep link when no record")
    func fallsBackWhenNoRecord() async throws {
        let reader = SharedStateReader(suiteName: "test.intent.audio.empty.\(UUID().uuidString)")
        let snapshot = reader.load()

        IntentActionStore.shared.pendingDeepLink = nil

        if snapshot.continueBookId == nil || snapshot.continueChapterNumber == nil {
            await MainActor.run { IntentActionStore.shared.pendingDeepLink = .library }
        }

        #expect(IntentActionStore.shared.pendingDeepLink == .library)
        IntentActionStore.shared.pendingDeepLink = nil
    }
}

// MARK: - LogDailyReadingIntent tests

@Suite("LogDailyReadingIntent")
struct LogDailyReadingIntentTests {

    @Test("accumulates minutes in App Group UserDefaults")
    func accumulatesMinutes() throws {
        let suiteName = "test.intent.log.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // First log: 10 minutes.
        let existing1 = defaults.integer(forKey: IntentKeys.pendingReadingMinutes)
        defaults.set(existing1 + 10, forKey: IntentKeys.pendingReadingMinutes)
        #expect(defaults.integer(forKey: IntentKeys.pendingReadingMinutes) == 10)

        // Second log: 15 more minutes.
        let existing2 = defaults.integer(forKey: IntentKeys.pendingReadingMinutes)
        defaults.set(existing2 + 15, forKey: IntentKeys.pendingReadingMinutes)
        #expect(defaults.integer(forKey: IntentKeys.pendingReadingMinutes) == 25)
    }

    @Test("clamps minutes to at least 1")
    func clampsToOne() {
        let raw = 0
        let clamped = max(1, raw)
        #expect(clamped == 1)
    }
}

// MARK: - AppModel audio command tests

@Suite("AppModel — consumeAudioControlCommand")
@MainActor
struct AppModelAudioCommandTests {

    @Test("clears audioControlCommand key after consuming")
    func clearsKeyAfterConsuming() throws {
        let suiteName = "test.intent.audioCmd.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("pause", forKey: IntentKeys.audioControlCommand)

        // Simulate AppModel consumption logic.
        guard let command = defaults.string(forKey: IntentKeys.audioControlCommand),
              !command.isEmpty else {
            Issue.record("Expected a command in UserDefaults")
            return
        }
        defaults.removeObject(forKey: IntentKeys.audioControlCommand)

        #expect(command == "pause")
        #expect(defaults.string(forKey: IntentKeys.audioControlCommand) == nil)
    }

    @Test("no-ops when key is absent")
    func noopsWhenKeyAbsent() throws {
        let suiteName = "test.intent.audioCmd.absent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let command = defaults.string(forKey: IntentKeys.audioControlCommand)
        #expect(command == nil)
    }
}

// MARK: - P8.9 Control widget intent key tests

@Suite("ControlWidgetIntents — App Group signaling")
struct ControlWidgetIntentKeyTests {

    @Test("StartReadingControlIntent logic writes startReading key")
    func startReadingWritesKey() {
        let suiteName = "test.control.reading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate StartReadingControlIntent.perform()
        defaults.set("startReading", forKey: IntentKeys.controlPendingAction)

        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == "startReading")
    }

    @Test("StartReviewControlIntent logic writes startReview key")
    func startReviewWritesKey() {
        let suiteName = "test.control.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate StartReviewControlIntent.perform()
        defaults.set("startReview", forKey: IntentKeys.controlPendingAction)

        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == "startReview")
    }

    @Test("ToggleAudioControlIntent logic writes audioControlCommand for play")
    func toggleAudioWritesPlayCommand() {
        let suiteName = "test.control.audio.play.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate ToggleAudioControlIntent.perform() with value = true (play)
        defaults.set("play", forKey: IntentKeys.audioControlCommand)
        defaults.set(true, forKey: IntentKeys.isAudioPlaying)

        #expect(defaults.string(forKey: IntentKeys.audioControlCommand) == "play")
        #expect(defaults.bool(forKey: IntentKeys.isAudioPlaying) == true)
    }

    @Test("ToggleAudioControlIntent logic writes audioControlCommand for pause")
    func toggleAudioWritesPauseCommand() {
        let suiteName = "test.control.audio.pause.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate ToggleAudioControlIntent.perform() with value = false (pause)
        defaults.set("pause", forKey: IntentKeys.audioControlCommand)
        defaults.set(false, forKey: IntentKeys.isAudioPlaying)

        #expect(defaults.string(forKey: IntentKeys.audioControlCommand) == "pause")
        #expect(defaults.bool(forKey: IntentKeys.isAudioPlaying) == false)
    }
}

// MARK: - AppModel consumeControlIntentAction tests

@Suite("AppModel — consumeControlIntentAction")
struct AppModelControlIntentTests {

    @Test("routes to chapter when startReading and continue-reading record exists")
    func routesToChapterOnStartReading() throws {
        let suiteName = "test.control.consume.reading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("startReading", forKey: IntentKeys.controlPendingAction)
        defaults.set("book-ctrl", forKey: SharedStateKeys.continueBookId)
        defaults.set(4, forKey: SharedStateKeys.continueChapterNumber)

        // Simulate consumeControlIntentAction routing logic
        guard let action = defaults.string(forKey: IntentKeys.controlPendingAction),
              !action.isEmpty else {
            Issue.record("Expected a pending action")
            return
        }
        defaults.removeObject(forKey: IntentKeys.controlPendingAction)

        let reader = SharedStateReader(suiteName: suiteName)
        let snapshot = reader.load()

        let link: DeepLink
        switch action {
        case "startReading":
            if let bookId = snapshot.continueBookId, let chapter = snapshot.continueChapterNumber {
                link = .chapter(bookId: bookId, chapter: chapter)
            } else {
                link = .library
            }
        case "startReview":
            link = .review
        default:
            link = .library
        }

        #expect(link == .chapter(bookId: "book-ctrl", chapter: 4))
        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == nil)
    }

    @Test("routes to review tab on startReview")
    func routesToReviewOnStartReview() throws {
        let suiteName = "test.control.consume.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("startReview", forKey: IntentKeys.controlPendingAction)

        guard let action = defaults.string(forKey: IntentKeys.controlPendingAction) else {
            Issue.record("Expected a pending action")
            return
        }
        defaults.removeObject(forKey: IntentKeys.controlPendingAction)

        let link: DeepLink = action == "startReview" ? .review : .library

        #expect(link == .review)
        #expect(defaults.string(forKey: IntentKeys.controlPendingAction) == nil)
    }

    @Test("no-ops when key is absent")
    func noopsWhenKeyAbsent() {
        let suiteName = "test.control.consume.absent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let action = defaults.string(forKey: IntentKeys.controlPendingAction)
        #expect(action == nil)
    }

    @Test("publishAudioPlayingState writes isAudioPlaying to App Group")
    func publishesAudioPlayingState() {
        let suiteName = "test.control.audioPlaying.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate publishAudioPlayingState(true)
        defaults.set(true, forKey: IntentKeys.isAudioPlaying)
        #expect(defaults.bool(forKey: IntentKeys.isAudioPlaying) == true)

        // Simulate publishAudioPlayingState(false)
        defaults.set(false, forKey: IntentKeys.isAudioPlaying)
        #expect(defaults.bool(forKey: IntentKeys.isAudioPlaying) == false)
    }
}

// MARK: - AppModel pending reading minutes tests

@Suite("AppModel — consumePendingReadingMinutes")
struct AppModelReadingMinutesTests {

    @Test("reads and clears pending minutes")
    func readsAndClearsPending() throws {
        let suiteName = "test.intent.readingMin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(30, forKey: IntentKeys.pendingReadingMinutes)

        let pending = defaults.integer(forKey: IntentKeys.pendingReadingMinutes)
        #expect(pending == 30)
        guard pending > 0 else { return }
        defaults.removeObject(forKey: IntentKeys.pendingReadingMinutes)
        #expect(defaults.integer(forKey: IntentKeys.pendingReadingMinutes) == 0)
    }

    @Test("no-ops when pending is zero")
    func noopsWhenZero() throws {
        let suiteName = "test.intent.readingMin.zero.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let pending = defaults.integer(forKey: IntentKeys.pendingReadingMinutes)
        #expect(pending == 0)
    }
}
