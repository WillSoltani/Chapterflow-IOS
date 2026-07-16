import XCTest

/// XCUITests for the sign-in flow.
///
/// Two perspectives are covered:
///
/// 1. **Unauthenticated state** — the app shows the WelcomeView / auth forms.
///    Fields, buttons and validation states are verified.
/// 2. **Pre-authenticated state** (bypass) — the app lands directly on the
///    main tab shell.  Verifies the home tab loads with stub catalog data.
///
/// The stub server (``CF_STUB_SERVER=1``) satisfies all REST API calls with
/// fixture-backed responses; real Cognito is never contacted.
final class SignInFlowTests: CFUITestCase {

    // MARK: - Unauthenticated state

    /// Launch without auth bypass and verify the auth screen appears.
    func testAuthScreenAppearsWhenNotSignedIn() throws {
        app.terminate()

        let freshApp = XCUIApplication()
        freshApp.launchEnvironment[TestEnv.stubServer] = "1"
        freshApp.launchEnvironment[TestEnv.hermeticConfiguration] = "1"
        // Deliberately omit bypassAuth so the app starts unauthenticated.
        freshApp.launch()
        defer { freshApp.terminate() }

        let createAccount = freshApp.buttons["Create an account"]
        let appleButton = freshApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'apple'")
        ).firstMatch
        let logInButton = freshApp.buttons["Already have an account? Log in"]

        XCTAssertTrue(createAccount.waitForExistence(timeout: 10))
        XCTAssertTrue(logInButton.waitForExistence(timeout: 3))
        XCTAssertFalse(appleButton.exists, "Unavailable Apple sign-in must not expose a false-success control")
    }

    /// Navigate to the log-in form and verify the field layout.
    func testLogInFormHasExpectedFields() throws {
        app.terminate()

        let freshApp = XCUIApplication()
        freshApp.launchEnvironment[TestEnv.stubServer] = "1"
        freshApp.launchEnvironment[TestEnv.hermeticConfiguration] = "1"
        freshApp.launch()
        defer { freshApp.terminate() }

        // Tap through to the log-in screen.
        let logInButton = freshApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'log in' OR label CONTAINS[c] 'sign in'")
        ).firstMatch

        XCTAssertTrue(logInButton.waitForExistence(timeout: 10), "Signed-out hermetic launch must show Log In")
        logInButton.tap()

        // The log-in form must contain an email field and a password field.
        let emailField    = freshApp.textFields.firstMatch
        let passwordField = freshApp.secureTextFields.firstMatch

        XCTAssert(
            emailField.waitForExistence(timeout: 8),
            "Log-in form must have an email text field"
        )
        XCTAssert(
            passwordField.waitForExistence(timeout: 5),
            "Log-in form must have a password secure field"
        )
    }

    /// Verify the sign-in button is disabled until both fields are populated.
    func testSignInButtonDisabledWhenFieldsEmpty() throws {
        app.terminate()

        let freshApp = XCUIApplication()
        freshApp.launchEnvironment[TestEnv.stubServer] = "1"
        freshApp.launchEnvironment[TestEnv.hermeticConfiguration] = "1"
        freshApp.launch()
        defer { freshApp.terminate() }

        let logInButton = freshApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'log in' OR label CONTAINS[c] 'sign in'")
        ).firstMatch

        XCTAssertTrue(logInButton.waitForExistence(timeout: 10), "Signed-out hermetic launch must show Log In")
        logInButton.tap()

        let submitButton = freshApp.buttons["Log In"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        XCTAssertFalse(submitButton.isEnabled, "Log In must remain disabled while credentials are empty")
    }

    // MARK: - Authenticated state (bypass)

    /// With auth bypass, the main tab shell must appear immediately.
    func testShellAppearsWithAuthBypass() {
        assertShellLoaded()
    }

    /// Tab bar must contain at least 3 tabs.
    func testTabBarHasExpectedTabs() {
        let tabBar = app.tabBars.firstMatch
        XCTAssert(tabBar.waitForExistence(timeout: 20), "Tab bar must appear")
        XCTAssertGreaterThanOrEqual(
            tabBar.buttons.count, 3,
            "Tab bar should have at least 3 tabs (Home, Library, Settings)"
        )
    }

    /// The app title / home content renders without an error state.
    func testHomeLoadsWithStubData() {
        assertShellLoaded()
        AppRobot(app: app).assertNoErrorState()
    }

    // MARK: - Configuration boundary

    /// With no test flags, the supplied Debug configuration remains unchanged.
    /// The CI-style placeholder build must therefore fail closed.
    func testNormalDebugConfigurationRemainsUntouchedWithoutTestFlags() {
        app.terminate()

        let normalDebugApp = XCUIApplication()
        normalDebugApp.launch()
        defer { normalDebugApp.terminate() }

        XCTAssertTrue(
            normalDebugApp.scrollViews["invalid-development-configuration"]
                .waitForExistence(timeout: 10),
            "A no-flag Debug launch must not synthesize a service configuration"
        )
        XCTAssertFalse(normalDebugApp.tabBars.firstMatch.exists)
    }

    /// Auth bypass seeds only the local session. Without both service-test flags,
    /// it must not select the synthetic API/Cognito configuration.
    func testAuthBypassAloneDoesNotActivateHermeticConfiguration() {
        app.terminate()

        let bypassOnlyApp = XCUIApplication()
        bypassOnlyApp.launchEnvironment[TestEnv.bypassAuth] = "1"
        bypassOnlyApp.launch()
        defer { bypassOnlyApp.terminate() }

        XCTAssertTrue(
            bypassOnlyApp.scrollViews["invalid-development-configuration"]
                .waitForExistence(timeout: 10),
            "Auth bypass alone must leave the supplied placeholder configuration invalid"
        )
        XCTAssertFalse(bypassOnlyApp.tabBars.firstMatch.exists)
    }

    /// A normal launch using the committed example placeholders must stop at
    /// the dedicated setup root before any auth or live product UI appears.
    func testPlaceholderConfigurationFailsClosedBeforeAuthUI() {
        app.terminate()

        let normalDebugApp = XCUIApplication()
        normalDebugApp.launchEnvironment[TestEnv.stubServer] = "1"
        normalDebugApp.launchEnvironment[TestEnv.invalidConfiguration] = "1"
        normalDebugApp.launch()
        defer { normalDebugApp.terminate() }

        XCTAssertTrue(
            normalDebugApp.scrollViews["invalid-development-configuration"]
                .waitForExistence(timeout: 10),
            "Placeholder Debug configuration must show the setup root"
        )
        let identifiedElements = normalDebugApp.descendants(matching: .any)
        XCTAssertTrue(identifiedElements["invalid-config-heading"].exists)
        XCTAssertTrue(identifiedElements["invalid-config-guidance"].exists)
        let supportCode = identifiedElements["invalid-config-support-code"]
        XCTAssertTrue(supportCode.exists)
        XCTAssertEqual(supportCode.label, "Support code: CF-DEV-CFG-001")
        XCTAssertFalse(normalDebugApp.tabBars.firstMatch.exists)

        let login = normalDebugApp.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'log in' OR label CONTAINS[c] 'sign in'")
        ).firstMatch
        XCTAssertFalse(login.exists, "Invalid configuration must not reveal login UI")
    }

    /// The base test launch uses both explicit hermetic flags and therefore
    /// continues to reach the deterministic signed-in shell.
    func testExplicitHermeticConfigurationReachesTestShell() {
        assertShellLoaded()
        XCTAssertFalse(app.otherElements["invalid-development-configuration"].exists)
    }

    // MARK: -

    // CFUITestCase.needsAuth defaults to true; setUp() already applies bypass.
}

final class GuestBrowsingFlowTests: CFUITestCase {
    override var needsAuth: Bool { false }

    /// Signed-out guest entry must reach public Home and Library without creating an account scope.
    func testGuestBrowsingReachesPublicHomeAndLibrary() {
        let signedOutTransition = app.activityIndicators["Signing you out"]
        if signedOutTransition.waitForExistence(timeout: 2) {
            XCTAssertTrue(
                signedOutTransition.waitForNonExistence(timeout: 30),
                "Signed-out account teardown must finish before guest entry is presented"
            )
        }

        let browseButton = app.buttons[
            "Continue browsing without creating an account"
        ]
        XCTAssertTrue(
            browseButton.waitForExistence(timeout: 10),
            "Signed-out launch must expose the guest browsing action"
        )
        browseButton.tap()

        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 20),
            "Guest entry must reach the tab shell"
        )
        XCTAssertTrue(
            app.navigationBars["Home"].waitForExistence(timeout: 20),
            "Guest Home must render"
        )

        let libraryTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'librar'")
        ).firstMatch
        XCTAssertTrue(
            libraryTab.waitForExistence(timeout: 5),
            "Guest Library tab must be reachable"
        )
        // The guest account affordance occupies the upper part of the iOS 26
        // tab-bar hit region; select the exposed lower portion of Library.
        libraryTab.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        ).tap()

        XCTAssertTrue(
            app.navigationBars["Library"].waitForExistence(timeout: 20),
            "Guest Library must render"
        )
        XCTAssertTrue(
            app.cells.firstMatch.waitForExistence(timeout: 60),
            "Guest Library must show catalog content from the stub server"
        )
    }
}
