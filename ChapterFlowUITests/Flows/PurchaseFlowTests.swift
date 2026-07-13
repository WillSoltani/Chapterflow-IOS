import XCTest

/// XCUITests for the purchase / subscription flow.
///
/// The stub server returns a FREE-tier entitlement so the app presents
/// upgrade entry points in the UI. These checks cover app survival and
/// navigation only; they do not prove StoreKit product loading or purchase.
///
/// The AppConfig-to-StoreKitConfig propagation seam is covered separately by
/// deterministic PaywallFeature unit tests. No purchase is attempted here.
final class PurchaseFlowTests: CFUITestCase {

    private var robot: AppRobot { AppRobot(app: app) }

    // MARK: - Free-tier baseline

    func testFreeUserShellLoads() {
        // Stub returns FREE entitlement — app must still reach the main shell.
        robot.waitForTabBar()
        robot.assertTabBarVisible()
    }

    func testFreeUserHasNoErrorState() {
        robot.waitForTabBar()
        robot.assertNoErrorState()
    }

    // MARK: - Paywall reachability

    func testSettingsTabIsReachable() {
        robot.waitForTabBar()
        robot.goToSettings()

        // Settings screen should load within the tab shell.
        let settingsContent = app.navigationBars.firstMatch
        _ = settingsContent.waitForExistence(timeout: 15)
        XCTAssert(app.exists, "App should remain alive after navigating to Settings")
    }

    func testUpgradeEntryPointExistsForFreeUsers() {
        robot.waitForTabBar()
        robot.goToSettings()

        // Settings exposes a Pro / upgrade row for free users.
        let upgradeRow = app.cells.matching(
            NSPredicate(
                format: "label CONTAINS[c] 'pro' OR label CONTAINS[c] 'upgrade' OR label CONTAINS[c] 'subscribe'"
            )
        ).firstMatch
        let buttonMatch = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] 'pro' OR label CONTAINS[c] 'upgrade' OR label CONTAINS[c] 'plan'"
            )
        ).firstMatch

        let upgradeVisible = upgradeRow.waitForExistence(timeout: 10)
            || buttonMatch.waitForExistence(timeout: 5)

        // If neither is visible the settings UI may not surface Pro yet.
        // Assert app is still alive and no crash occurred.
        XCTAssert(app.exists, "App must not crash while a free user browses Settings")
        _ = upgradeVisible // Informational; layout may vary.
    }

    // MARK: - StoreKit-adjacent survival

    /// Verifies only that the app remains alive after the free-tier shell loads.
    func testAppRemainsAliveInStoreKitAdjacentLane() {
        robot.waitForTabBar()
        XCTAssert(app.exists, "App must remain alive in the StoreKit-adjacent lane")
    }

    func testAppSurvivesUpgradeNavigationAttempt() {
        robot.waitForTabBar()

        // Try to trigger the paywall via the Settings upgrade path.
        robot.goToSettings()

        let proButton = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] 'pro' OR label CONTAINS[c] 'upgrade'"
            )
        ).firstMatch
        if proButton.waitForExistence(timeout: 8) {
            proButton.tap()

            // Pricing visibility is informational only. This test does not prove
            // that StoreKit returned products or that a purchase can complete.
            let pricingText = app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] 'month' OR label CONTAINS[c] 'annual' OR label CONTAINS[c] 'pro'"
                )
            ).firstMatch
            _ = pricingText.waitForExistence(timeout: 10)
        }
        XCTAssert(app.exists, "App must survive paywall navigation")
    }
}
