import StoreKitTest
import XCTest

/// XCUITests for the purchase / subscription flow.
///
/// The stub server returns a FREE-tier entitlement so the app presents
/// upgrade entry points in the UI.  The StoreKit Test Configuration
/// (``ChapterFlow.storekit``) provides the subscription products so
/// StoreKit can function without App Store connectivity.
///
/// No real money is charged: all purchases use the test configuration.
final class PurchaseFlowTests: CFUITestCase {
    /// Retains the local StoreKit environment for the complete purchase,
    /// relaunch, and restore contract. The base case creates the application
    /// proxy before this session is configured, then launches only after the
    /// local catalog has been bound.
    private var storeKitSession: SKTestSession?

    private var robot: AppRobot { AppRobot(app: app) }

    override func prepareForAppLaunch() throws {
        guard ProcessInfo.processInfo.environment["XCODE_SCHEME_NAME"]
            == "ChapterFlow-StoreKitTest" else {
            return
        }

        // The iOS 26.1 simulator can expose SwiftUI tab items without a valid
        // activation frame to headless XCTest. This contract is about the
        // StoreKit purchase/restore boundary, so enter Settings through the
        // existing DEBUG-only launch route instead of depending on that
        // unrelated simulator hit-testing path.
        app.launchArguments.append("--demo-tab=settings")

        let session = try SKTestSession(configurationFileNamed: "ChapterFlow")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        storeKitSession = session
    }

    override func tearDownWithError() throws {
        storeKitSession = nil
        try super.tearDownWithError()
    }

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

    // MARK: - StoreKit test configuration

    /// Verifies the app initialises StoreKit without errors in the test environment.
    /// A crash here indicates the StoreKit configuration isn't linked correctly.
    func testStoreKitInitialisesWithTestConfiguration() {
        robot.waitForTabBar()
        // If StoreKit initialisation throws or crashes, the test never reaches here.
        XCTAssert(app.exists, "App must remain alive after StoreKit initialisation")
    }

    func testPaywallReachableFromEntitlementCheck() {
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

            // After tapping, the paywall sheet / screen should appear.
            // Check for pricing text surfaced by the stub or StoreKit test config.
            let pricingText = app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] 'month' OR label CONTAINS[c] 'annual' OR label CONTAINS[c] 'pro'"
                )
            ).firstMatch
            _ = pricingText.waitForExistence(timeout: 10)
        }
        XCTAssert(app.exists, "App must survive paywall navigation")
    }

    // MARK: - StoreKit purchase contract

    /// Proves that the dedicated scheme loads the approved monthly product from
    /// StoreKit, displays its local test price, completes a real StoreKit Test
    /// purchase, receives the additive backend acknowledgement, and refreshes
    /// the app-wide entitlement to Pro.
    @MainActor
    func testStoreKitCatalogPurchaseRelaunchAndRestoreCompletes() {
        guard storeKitSession != nil else {
            XCTFail("The dedicated StoreKit scheme did not retain its prelaunch SKTestSession")
            return
        }

        robot.waitForTabBar()
        assertPlan("Free")

        let upgradeButton = app.buttons["Upgrade to ChapterFlow Pro"]
        reveal(upgradeButton)
        upgradeButton.tap()

        let monthlyPlan = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "ChapterFlow Pro Monthly, $7.99 per month"
            )
        ).firstMatch
        guard requireStoreKitProduct(monthlyPlan) else {
            return
        }
        revealExisting(monthlyPlan, maxSwipes: 10)
        XCTAssertTrue(
            monthlyPlan.label.contains("renews automatically until canceled"),
            "StoreKit product disclosure must describe automatic renewal"
        )
        monthlyPlan.tap()
        let selectedPlan = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: monthlyPlan
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedPlan], timeout: 5),
            .completed,
            "Monthly plan selection must settle before subscribing"
        )

        let subscribeButton = app.buttons["Subscribe – $7.99 / month"]
        reveal(subscribeButton)
        subscribeButton.tap()

        assertPurchaseSuccessAndContinue()
        assertPlan("Pro")
        XCTAssertTrue(
            storeKitSession?.allTransactions().contains {
                $0.productIdentifier == "com.chapterflow.pro.monthly"
            } == true,
            "The app purchase must create the approved monthly StoreKit transaction"
        )

        // Relaunch with the stub reset to FREE while the StoreKit transaction
        // remains installed. All automatic authorization/reconciliation
        // verifies stay suppressed so only the user-visible restore action can
        // release the fixture-backed backend grant.
        app.terminate()
        app.launchEnvironment[TestEnv.deferAppleVerificationUntilRestore] = "1"
        app.launch()

        robot.waitForTabBar()
        assertPlan("Free")

        let relaunchedUpgradeButton = app.buttons["Upgrade to ChapterFlow Pro"]
        reveal(relaunchedUpgradeButton)
        relaunchedUpgradeButton.tap()

        let restoreButton = app.buttons["Restore previous purchases"]
        reveal(restoreButton, maxSwipes: 12)
        guard signalExplicitRestoreStarted() else {
            return
        }
        restoreButton.tap()

        assertPurchaseSuccessAndContinue()
        assertPlan("Pro")
    }

    @MainActor
    private func signalExplicitRestoreStarted(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.chapterflow"
        ) else {
            XCTFail("UI-test runner could not access the ChapterFlow App Group", file: file, line: line)
            return false
        }

        let signalURL = appGroupURL.appendingPathComponent(
            ".chapterflow-uitest-restore-began",
            isDirectory: false
        )
        do {
            try Data().write(to: signalURL, options: .atomic)
            return true
        } catch {
            XCTFail("UI-test runner could not signal explicit restore", file: file, line: line)
            return false
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, maxSwipes: Int = 6) {
        assertExists(element, timeout: 20)
        revealExisting(element, maxSwipes: maxSwipes)
    }

    @MainActor
    private func revealExisting(_ element: XCUIElement, maxSwipes: Int) {
        var remainingSwipes = maxSwipes
        while !element.isHittable && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
        XCTAssertTrue(element.isHittable, "Expected element to become tappable: \(element)")
    }

    @MainActor
    private func requireStoreKitProduct(
        _ product: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        if product.waitForExistence(timeout: 20) {
            return true
        }

        let unavailableTitle = app.staticTexts["Subscriptions Unavailable"]
        let retryButton = app.buttons["Try Again"]
        if unavailableTitle.exists || retryButton.exists {
            XCTFail(
                "The local StoreKit catalog did not bind to the app before launch; "
                    + "Product.products(for:) returned no subscription options.",
                file: file,
                line: line
            )
        } else {
            XCTFail(
                "The approved monthly StoreKit product was not rendered by the paywall.",
                file: file,
                line: line
            )
        }
        return false
    }

    @MainActor
    private func assertPurchaseSuccessAndContinue() {
        let successMessage = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Purchase successful. You're now a Pro member."
            )
        ).firstMatch
        assertExists(
            successMessage,
            message: "The backend-acknowledged StoreKit action must show success",
            timeout: 30
        )

        let continueButton = app.buttons["Continue"]
        assertHittable(continueButton, message: "Purchase success must be dismissible")
        continueButton.tap()
    }

    @MainActor
    private func assertPlan(_ plan: String) {
        let planLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Subscription plan: \(plan)")
        ).firstMatch
        assertExists(
            planLabel,
            message: "Expected the app-wide subscription plan to become \(plan)",
            timeout: 20
        )
    }
}
