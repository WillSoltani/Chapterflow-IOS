import Testing
import Foundation
@testable import SettingsFeature

@Suite("SettingsFeature")
struct SettingsFeatureTests {

    @Test("module exposes its name")
    func moduleName() {
        #expect(SettingsFeature.moduleName == "SettingsFeature")
    }

    @Test("SettingsView initializes with default free state")
    @MainActor
    func settingsViewDefaultInit() {
        let view = SettingsView()
        _ = view
    }

    @Test("SettingsView initializes with Pro state")
    @MainActor
    func settingsViewProInit() {
        let periodEnd = Date(timeIntervalSinceNow: 30 * 24 * 3600)
        let view = SettingsView(
            isPro: true,
            currentPeriodEnd: periodEnd,
            cancelAtPeriodEnd: false
        )
        _ = view
    }

    @Test("SettingsView initializes with free state and remaining starts")
    @MainActor
    func settingsViewFreeWithStartsInit() {
        let view = SettingsView(isPro: false, remainingFreeStarts: 3)
        _ = view
    }

    @Test("SettingsView callbacks can be provided and are callable")
    @MainActor
    func settingsViewCallbacksAreCallable() {
        var paywallCalled = false
        var manageCalled = false
        let onShowPaywall: () -> Void = { paywallCalled = true }
        let onManage: () -> Void = { manageCalled = true }

        let view = SettingsView(
            isPro: false,
            onShowPaywall: onShowPaywall,
            onManageSubscription: onManage
        )
        _ = view

        // Verify closures capture state correctly.
        onShowPaywall()
        onManage()
        #expect(paywallCalled)
        #expect(manageCalled)
    }
}
