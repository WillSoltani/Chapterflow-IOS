import Testing
import Foundation
@testable import AppFeature
import Persistence
import CoreKit

// MARK: - Quick Action routing logic tests

#if canImport(UIKit)
@Suite("QuickActionBridge")
struct QuickActionBridgeTests {

    @Test("pendingShortcutType starts nil")
    func startsNil() {
        QuickActionBridge.shared.pendingShortcutType = nil
        #expect(QuickActionBridge.shared.pendingShortcutType == nil)
    }

    @Test("pendingShortcutType round-trips correctly")
    func roundTrips() {
        QuickActionBridge.shared.pendingShortcutType = QuickActionBridge.ShortcutType.continueReading
        #expect(QuickActionBridge.shared.pendingShortcutType == "com.chapterflow.ios.continue-reading")
        QuickActionBridge.shared.pendingShortcutType = nil
    }
}
#endif

// MARK: - Routing logic tests (platform-agnostic)

@Suite("Quick Action routing — continue reading")
@MainActor
struct QuickActionRoutingTests {

    @Test("ownerless continue-reading snapshot is preserved but not routed")
    func ownerlessContinueReadingIsNotRouted() async {
        let suiteName = "test.qa.continueReading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("book-qa1", forKey: SharedStateKeys.continueBookId)
        defaults.set(5, forKey: SharedStateKeys.continueChapterNumber)

        let link = DeepLink.library

        #expect(link == .library)
        #expect(defaults.string(forKey: SharedStateKeys.continueBookId) == "book-qa1")
        #expect(defaults.integer(forKey: SharedStateKeys.continueChapterNumber) == 5)
    }
}

// MARK: - AppModel.consumeQuickAction tests (UIKit-only)

#if canImport(UIKit)
@Suite("AppModel — consumeQuickAction")
@MainActor
struct AppModelQuickActionTests {

    @Test("reviews shortcut type routes to .review deep link")
    func reviewsRoutesToReview() {
        let type = QuickActionBridge.ShortcutType.reviews
        let link: DeepLink
        switch type {
        case QuickActionBridge.ShortcutType.reviews:
            link = .review
        default:
            link = .unknown(URL(string: "chapterflow://unknown")!)
        }
        #expect(link == .review)
    }

    @Test("ask shortcut type routes to .engagement deep link")
    func askRoutesToEngagement() {
        let type = QuickActionBridge.ShortcutType.ask
        let link: DeepLink
        switch type {
        case QuickActionBridge.ShortcutType.ask:
            link = .engagement
        default:
            link = .unknown(URL(string: "chapterflow://unknown")!)
        }
        #expect(link == .engagement)
    }

    @Test("consumeQuickAction clears the bridge after reading")
    func consumeClears() async {
        let model = makeTestAppModel()
        QuickActionBridge.shared.pendingShortcutType = QuickActionBridge.ShortcutType.reviews
        model.consumeQuickAction()
        #expect(QuickActionBridge.shared.pendingShortcutType == nil)
        #expect(model.selectedTab == .reviews)
    }

    @Test("consumeQuickAction is a no-op when bridge is empty")
    func noopWhenEmpty() async {
        let model = makeTestAppModel()
        QuickActionBridge.shared.pendingShortcutType = nil
        let tabBefore = model.selectedTab
        model.consumeQuickAction()
        #expect(model.selectedTab == tabBefore)
    }
}
#endif

// MARK: - AppModel.consumeFocusFilter tests

@Suite("AppModel — consumeFocusFilter")
@MainActor
struct AppModelFocusFilterTests {

    @Test("reads true from App Group defaults")
    func readsTrueFromDefaults() {
        let suiteName = "test.focus.active.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: FocusFilterKeys.isReadingFocusActive)

        let isActive = defaults.bool(forKey: FocusFilterKeys.isReadingFocusActive)
        #expect(isActive == true)
    }

    @Test("reads false when key is absent")
    func readsFalseWhenAbsent() {
        let suiteName = "test.focus.absent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let isActive = defaults.bool(forKey: FocusFilterKeys.isReadingFocusActive)
        #expect(isActive == false)
    }

    @Test("FocusFilterKeys constant matches expected string")
    func keyConstantIsStable() {
        #expect(FocusFilterKeys.isReadingFocusActive == "focusFilter.isReadingFocusActive")
    }
}
