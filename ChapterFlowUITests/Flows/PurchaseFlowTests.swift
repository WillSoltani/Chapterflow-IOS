import XCTest

/// XCUITests for the purchase / subscription flow.
///
/// The stub server returns a FREE-tier entitlement so the app presents
/// an upgrade entry point in Settings. These checks cover the fixture-backed
/// shell, exact Settings navigation, and presentation of the paywall shell.
/// They do not prove StoreKit product loading, localized pricing, purchase
/// initiation or completion, backend verification, entitlement activation,
/// or restore success.
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
    }

    func testFreeUserSettingsShowsUpgradeEntry() {
        robot.waitForTabBar()
        robot.goToSettings()

        XCTAssertTrue(
            app.buttons["settings-upgrade-to-pro"].waitForExistence(timeout: 10),
            "The deterministic free-tier Settings screen should expose its upgrade action"
        )
    }

    // MARK: - StoreKit-adjacent survival

    /// Verifies only that the app remains alive after the free-tier shell loads.
    func testAppRemainsAliveInStoreKitAdjacentLane() {
        robot.waitForTabBar()
        XCTAssert(app.exists, "App must remain alive in the StoreKit-adjacent lane")
    }

    func testSettingsUpgradePresentsPaywallShell() {
        robot.waitForTabBar()
        robot.goToSettings()

        let upgradeButton = app.buttons["settings-upgrade-to-pro"]
        XCTAssertTrue(
            upgradeButton.waitForExistence(timeout: 10),
            "The deterministic free-tier Settings screen should expose its upgrade action"
        )
        upgradeButton.tap()

        XCTAssertTrue(
            app.staticTexts["ChapterFlow Pro"].waitForExistence(timeout: 10),
            "The Settings upgrade action should present the Settings-context paywall shell"
        )
        XCTAssertTrue(
            app.buttons["Dismiss"].exists,
            "The presented paywall shell should expose its dismiss action"
        )
    }
}
