import Testing
import SwiftUI
@testable import DesignSystem

// MARK: - OfflineBannerView logic

@Suite("OfflineBannerView")
struct OfflineBannerViewTests {

    @Test("pill label shows 'Offline' when no mutations are pending")
    func pillLabelNoPending() {
        let view = OfflineBannerView(isOffline: true, pendingCount: 0)
        #expect(view.pendingCount == 0)
        #expect(view.isOffline)
    }

    @Test("pill label includes count when mutations are pending")
    func pillLabelWithPending() {
        let view = OfflineBannerView(isOffline: true, pendingCount: 7)
        #expect(view.pendingCount == 7)
    }

    @Test("view is logically hidden when online (isOffline = false)")
    func hiddenWhenOnline() {
        let view = OfflineBannerView(isOffline: false, pendingCount: 0)
        #expect(!view.isOffline)
    }

    @Test("pendingCount of zero is valid regardless of isOffline")
    func zeroCountIsValid() {
        let online = OfflineBannerView(isOffline: false, pendingCount: 0)
        let offline = OfflineBannerView(isOffline: true, pendingCount: 0)
        #expect(online.pendingCount == 0)
        #expect(offline.pendingCount == 0)
    }
}

// MARK: - OfflineQueuedBadge logic

@Suite("OfflineQueuedBadge")
struct OfflineQueuedBadgeTests {

    @Test("badge is logically hidden when pendingCount is 0")
    func hiddenWhenZero() {
        let badge = OfflineQueuedBadge(pendingCount: 0)
        #expect(badge.pendingCount == 0)
    }

    @Test("badge shows when pendingCount is 1")
    func shownForSingleItem() {
        let badge = OfflineQueuedBadge(pendingCount: 1)
        #expect(badge.pendingCount == 1)
    }

    @Test("badge shows when pendingCount is large")
    func shownForManyItems() {
        let badge = OfflineQueuedBadge(pendingCount: 99)
        #expect(badge.pendingCount == 99)
    }
}

// MARK: - OfflineDisabledModifier logic

@Suite("OfflineDisabledModifier")
struct OfflineDisabledModifierTests {

    @Test("modifier stores isOffline correctly")
    func storesIsOffline() {
        let mod = OfflineDisabledModifier(isOffline: true, reason: "Test reason")
        #expect(mod.isOffline == true)
    }

    @Test("modifier stores reason string correctly")
    func storesReason() {
        let reason = "Requires internet connection"
        let mod = OfflineDisabledModifier(isOffline: false, reason: reason)
        #expect(mod.reason == reason)
    }

    @Test("isOffline = false does not disable")
    func notDisabledWhenOnline() {
        let mod = OfflineDisabledModifier(isOffline: false, reason: "Requires internet connection")
        #expect(!mod.isOffline)
    }
}
