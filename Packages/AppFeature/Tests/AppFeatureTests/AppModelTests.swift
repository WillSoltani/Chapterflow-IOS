import Testing
import Foundation
@testable import AppFeature
import Models

@Suite("AppModel deep-link routing — custom scheme")
@MainActor
struct AppModelTests {

    @Test("book URL routes to library tab")
    func bookURLRoutesToLibrary() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
    }

    @Test("chapter URL routes to library tab")
    func chapterURLRoutesToLibrary() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123/chapter/3")!)
        #expect(model.selectedTab == .library)
    }

    @Test("review URL routes to reviews tab")
    func reviewURLRoutesToReviews() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("pair accept URL routes to profile tab")
    func pairAcceptRoutesToProfile() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
    }

    @Test("gift URL routes to profile tab and sets pendingGiftCode")
    func giftURLRoutesToProfile() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingGiftCode == "GIFTCODE")
    }

    @Test("referral URL routes to profile tab and sets pendingReferralCode")
    func referralURLRoutesToProfile() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://ref/ALICE42")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingReferralCode == "ALICE42")
    }

    @Test("paywall URL presents the paywall")
    func paywallURLPresentsPaywall() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://paywall")!)
        #expect(model.showPaywall)
    }

    @Test("journey URL routes to home tab")
    func journeyURLRoutesToHome() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://journey/j-summer")!)
        #expect(model.selectedTab == .home)
    }

    @Test("event URL routes to home tab")
    func eventURLRoutesToHome() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://event/ev-nov")!)
        #expect(model.selectedTab == .home)
    }

    @Test("unrecognised chapterflow path leaves tab unchanged")
    func unknownPathIgnored() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "chapterflow://unknown-feature")!)
        #expect(model.selectedTab == .home)
    }
}

// MARK: - Universal Link routing

@Suite("AppModel deep-link routing — Universal Links")
@MainActor
struct AppModelUniversalLinkTests {

    @Test("Universal Link book URL routes to library tab")
    func universalLinkBookRoutesToLibrary() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/book/abc123")!)
        #expect(model.selectedTab == .library)
    }

    @Test("Universal Link chapter URL routes to library tab")
    func universalLinkChapterRoutesToLibrary() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/book/abc123/chapter/3")!)
        #expect(model.selectedTab == .library)
    }

    @Test("Universal Link review URL routes to reviews tab")
    func universalLinkReviewRoutesToReviews() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("Universal Link pair accept URL routes to profile tab")
    func universalLinkPairAcceptRoutesToProfile() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingPairAcceptCode == "XYZ")
    }

    @Test("Universal Link gift URL routes to profile and sets code")
    func universalLinkGiftRoutesToProfile() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingGiftCode == "GIFTCODE")
    }

    @Test("Universal Link paywall URL presents paywall")
    func universalLinkPaywallPresentsPaywall() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/paywall")!)
        #expect(model.showPaywall)
    }

    @Test("wrong-domain https URL is ignored; tab stays at default")
    func wrongDomainIgnored() async {
        let model = makeTestAppModel()
        model.handle(url: URL(string: "https://evil.com/book/abc123")!)
        #expect(model.selectedTab == .home)
    }
}

// MARK: - Handoff

@Suite("AppModel — Handoff")
@MainActor
struct AppModelHandoffTests {

    @Test("handleHandoff sets pendingHandoffFlow with correct bookId and chapter")
    func handoffSetsFlow() {
        let model = makeTestAppModel()
        model.handleHandoff(bookId: "book-abc", chapterNumber: 3, variantFamilyRaw: "EMH")
        #expect(model.pendingHandoffFlow?.bookId == "book-abc")
        #expect(model.pendingHandoffFlow?.chapterNumber == 3)
        #expect(model.pendingHandoffFlow?.variantFamily == .emh)
    }

    @Test("handleHandoff with nil variantFamily defaults to .emh")
    func handoffDefaultsVariantFamily() {
        let model = makeTestAppModel()
        model.handleHandoff(bookId: "book-xyz", chapterNumber: 1, variantFamilyRaw: nil)
        #expect(model.pendingHandoffFlow?.variantFamily == .emh)
    }

    @Test("handleHandoff with unknown variantFamily rawValue uses .unknown")
    func handoffUnknownVariantFamily() {
        let model = makeTestAppModel()
        model.handleHandoff(bookId: "book-xyz", chapterNumber: 2, variantFamilyRaw: "FUTURE_FORMAT")
        #expect(model.pendingHandoffFlow?.variantFamily == .unknown("FUTURE_FORMAT"))
    }
}

// MARK: - Guest mode

@Suite("AppModel — guest mode")
@MainActor
struct AppModelGuestTests {

    @Test("enterGuestMode sets isGuestMode to true")
    func enterGuestModeSetsFlag() {
        let model = makeTestAppModel()
        #expect(!model.isGuestMode)
        model.enterGuestMode()
        #expect(model.isGuestMode)
    }

    @Test("requestAuth sets pendingAuthIntent and showAuthGate")
    func requestAuthSetsIntentAndShowsGate() {
        let model = makeTestAppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .startBook(bookId: "b-test", variantFamily: .emh))
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent == .startBook(bookId: "b-test", variantFamily: .emh))
    }

    @Test("requestAuth with .none sets showAuthGate without a specific intent")
    func requestAuthNoneShowsGate() {
        let model = makeTestAppModel()
        model.enterGuestMode()
        model.requestAuth(intent: .none)
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent.isNone)
    }

    @Test("guest book URL goes to library, not auth gate")
    func guestBookURLRoutesToLibrary() {
        let model = makeTestAppModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
        #expect(!model.showAuthGate)
    }

    @Test("guest gated URL triggers auth gate")
    func guestGatedURLTriggersAuthGate() {
        let model = makeTestAppModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.showAuthGate)
    }

    @Test("replayPendingIntent with .none clears intent and guest mode")
    func replayNoneIntentClearsState() async {
        let model = makeTestAppModel()
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
        let model = makeTestAppModel()
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
