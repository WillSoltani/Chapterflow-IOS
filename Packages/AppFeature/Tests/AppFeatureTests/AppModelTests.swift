import Testing
import Foundation
@testable import AppFeature
import Models

@Suite("AppModel deep-link routing")
@MainActor
struct AppModelTests {

    @Test("book URL routes to library tab")
    func bookURLRoutesToLibrary() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
    }

    @Test("chapter URL routes to library tab")
    func chapterURLRoutesToLibrary() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123/chapter/3")!)
        #expect(model.selectedTab == .library)
    }

    @Test("review URL routes to reviews tab")
    func reviewURLRoutesToReviews() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("pair accept URL routes to profile tab")
    func pairAcceptRoutesToProfile() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
    }

    @Test("gift URL routes to profile tab")
    func giftURLRoutesToProfile() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
    }

    @Test("unknown scheme is ignored; tab stays at default")
    func unknownSchemeIgnored() async {
        let model = AppModel()
        model.handle(url: URL(string: "https://chapterflow.app/book/abc123")!)
        #expect(model.selectedTab == .home)
    }

    @Test("unrecognised chapterflow path leaves tab unchanged")
    func unknownPathIgnored() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://unknown-feature")!)
        #expect(model.selectedTab == .home)
    }
}

@Suite("AppModel — guest mode")
@MainActor
struct AppModelGuestTests {

    @Test("enterGuestMode sets isGuestMode to true")
    func enterGuestModeSetsFlag() {
        let model = AppModel()
        #expect(!model.isGuestMode)
        model.enterGuestMode()
        #expect(model.isGuestMode)
    }

    @Test("requestAuth sets pendingAuthIntent and showAuthGate")
    func requestAuthSetsIntentAndShowsGate() {
        let model = AppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .startBook(bookId: "b-test", variantFamily: .emh))
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent == .startBook(bookId: "b-test", variantFamily: .emh))
    }

    @Test("requestAuth with .none sets showAuthGate without a specific intent")
    func requestAuthNoneShowsGate() {
        let model = AppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .none)
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent.isNone)
    }

    @Test("guest book URL goes to library, not auth gate")
    func guestBookURLRoutesToLibrary() {
        let model = AppModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
        #expect(!model.showAuthGate)
    }

    @Test("guest gated URL triggers auth gate")
    func guestGatedURLTriggersAuthGate() {
        let model = AppModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.showAuthGate)
    }

    @Test("replayPendingIntent with .none clears intent and guest mode")
    func replayNoneIntentClearsState() async {
        let model = AppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .none)

        var readingFlowSet: ReadingFlow?
        await model.replayPendingIntent { readingFlowSet = $0 }

        #expect(model.pendingAuthIntent.isNone)
        #expect(!model.isGuestMode)
        #expect(readingFlowSet == nil)
    }

    @Test("replayPendingIntent with .startBook clears intent and guest mode")
    func replayStartBookClearsGuestMode() async {
        let model = AppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .startBook(bookId: "b-atomic-habits", variantFamily: .emh))

        var readingFlowSet: ReadingFlow?
        await model.replayPendingIntent { readingFlowSet = $0 }

        // In tests the live API call fails (no auth), so the fallback routes to library.
        // We assert intent and guest mode are cleared regardless.
        #expect(model.pendingAuthIntent.isNone)
        #expect(!model.isGuestMode)
        // Either the reading flow opened (on-device with a valid session) or
        // we fell back to the library tab — both are acceptable outcomes.
        let openedReaderOrNavigatedToLibrary = readingFlowSet != nil || model.selectedTab == .library
        #expect(openedReaderOrNavigatedToLibrary)
    }
}
