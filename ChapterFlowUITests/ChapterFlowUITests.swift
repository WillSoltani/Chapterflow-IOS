import XCTest

// MARK: - Environment keys

/// Environment variable keys used by the XCUITest stub infrastructure.
/// Set these in ``XCUIApplication.launchEnvironment`` before calling ``launch()``.
enum TestEnv {
    /// Set to "1" to register ``CFStubURLProtocol`` and serve fixture JSON for all requests.
    static let stubServer  = "CF_STUB_SERVER"
    /// Set with both hermetic flags to activate a fixed in-memory test session.
    static let bypassAuth  = "CF_UITEST_BYPASS_AUTH"
    /// Set with the stub server to select the explicit synthetic API/Cognito config.
    static let hermeticConfiguration = "CF_HERMETIC_TEST_CONFIGURATION"
    /// Set to exercise the invalid-configuration root using safe placeholders.
    static let invalidConfiguration = "CF_INVALID_TEST_CONFIGURATION"
    /// Holds required storage open so the lightweight first frame is observable.
    static let suspendBootstrapStorage = "CF_BOOTSTRAP_SUSPEND_STORAGE"
    /// Delays protected-data availability, then resumes bootstrap automatically.
    static let waitForProtectedData = "CF_BOOTSTRAP_WAIT_PROTECTED_DATA"
    /// Makes the first storage attempt fail; retry uses the live hermetic path.
    static let failBootstrapStorageOnce = "CF_BOOTSTRAP_FAIL_STORAGE_ONCE"
    /// Fails required session setup after storage succeeds.
    static let failBootstrapSession = "CF_BOOTSTRAP_FAIL_SESSION"
    /// Set to "1" to enable the optional smoke lane (hits real prod API, non-blocking).
    static let realAPI     = "CF_REAL_API"
}

// MARK: - Bootstrap state machine

final class BootstrapPreparingUITests: CFUITestCase {
    override var needsAuth: Bool { false }
    override var extraLaunchEnvironment: [String: String] {
        [TestEnv.suspendBootstrapStorage: "1"]
    }

    func testFirstFrameAppearsBeforeRequiredStorageCompletes() {
        assertExists(
            app.descendants(matching: .any)["bootstrap-preparing"],
            message: "Preparing surface should be the first actionable frame"
        )
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["Sign In"].exists)
    }
}

final class BootstrapStorageRecoveryUITests: CFUITestCase {
    override var extraLaunchEnvironment: [String: String] {
        [TestEnv.failBootstrapStorageOnce: "1"]
    }

    func testStorageFailureRetriesToTheSingleLiveShell() {
        assertExists(
            app.descendants(matching: .any)["bootstrap-storage-unavailable"],
            message: "Required storage failure should have a dedicated surface"
        )
        XCTAssertTrue(app.staticTexts["Support code: CF-BOOT-STORAGE-STORE-001"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let retry = app.buttons["bootstrap-retry"]
        assertExists(retry)
        retry.tap()

        assertShellLoaded()
        XCTAssertFalse(app.descendants(matching: .any)["bootstrap-storage-unavailable"].exists)
    }
}

final class BootstrapProtectedDataRecoveryUITests: CFUITestCase {
    override var extraLaunchEnvironment: [String: String] {
        [TestEnv.waitForProtectedData: "1"]
    }

    func testProtectedDataWaitRecoversWithoutManualRetry() {
        assertExists(
            app.descendants(matching: .any)["bootstrap-protected-data-waiting"],
            message: "Protected data should use a distinct waiting surface"
        )
        XCTAssertFalse(app.buttons["bootstrap-retry"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        assertShellLoaded()
        XCTAssertFalse(
            app.descendants(matching: .any)["bootstrap-protected-data-waiting"].exists
        )
    }
}

final class BootstrapSessionFailureUITests: CFUITestCase {
    override var needsAuth: Bool { false }
    override var extraLaunchEnvironment: [String: String] {
        [TestEnv.failBootstrapSession: "1"]
    }

    func testRequiredSessionFailureNeverPublishesAuthOrTabShell() {
        assertExists(
            app.descendants(matching: .any)["bootstrap-session-configuration-failed"],
            message: "Required session failure should have a dedicated surface"
        )
        XCTAssertTrue(app.staticTexts["Support code: CF-BOOT-SESSION-001"].exists)
        XCTAssertTrue(app.buttons["bootstrap-retry"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["Sign In"].exists)
    }
}

final class BootstrapPrecedenceUITests: CFUITestCase {
    override var needsAuth: Bool { false }
    override var extraLaunchEnvironment: [String: String] {
        [
            TestEnv.invalidConfiguration: "1",
            TestEnv.failBootstrapStorageOnce: "1",
        ]
    }

    func testInvalidConfigurationPrecedesStorageInjection() {
        assertExists(
            app.descendants(matching: .any)["invalid-development-configuration"],
            message: "Invalid configuration must fail before storage starts"
        )
        XCTAssertFalse(app.descendants(matching: .any)["bootstrap-storage-unavailable"].exists)
        XCTAssertFalse(app.buttons["bootstrap-retry"].exists)
    }
}

// MARK: - Base test class

/// Base class for all ChapterFlow XCUITests.
///
/// Subclasses automatically get:
/// - ``CF_STUB_SERVER=1`` → all network calls return fixture data.
/// - ``CF_UITEST_BYPASS_AUTH=1`` when ``needsAuth`` is true → the app
///   presents as signed-in without performing a real Cognito handshake.
///
/// Override ``needsAuth`` to control the auth seeding and
/// ``extraLaunchEnvironment`` to pass additional env vars.
class CFUITestCase: XCTestCase {

    // XCTest always calls setUp/tearDown on the main thread so accessing
    // XCUIApplication here is safe at runtime despite compiler actor warnings.
    private(set) var app: XCUIApplication! // swiftlint:disable:this implicitly_unwrapped_optional

    /// Return `true` (default) to launch with the triple-gated synthetic session.
    /// Return `false` to start the app in the unauthenticated state.
    var needsAuth: Bool { true }

    /// Additional launch-environment entries applied before ``app.launch()``.
    var extraLaunchEnvironment: [String: String] { [:] }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment[TestEnv.stubServer] = "1"
        app.launchEnvironment[TestEnv.hermeticConfiguration] = "1"
        if needsAuth {
            app.launchEnvironment[TestEnv.bypassAuth] = "1"
        }
        for (key, value) in extraLaunchEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // MARK: - Convenience assertions

    /// Waits for `element` to exist within `timeout` seconds.
    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Asserts that `element` exists within `timeout` seconds; fails the test if not.
    func assertExists(
        _ element: XCUIElement,
        message: String = "",
        timeout: TimeInterval = 15,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let msg = message.isEmpty ? "\(element.description) should exist" : message
        XCTAssert(element.waitForExistence(timeout: timeout), msg, file: file, line: line)
    }

    /// Asserts the main tab bar is visible (confirms the app reached the shell).
    func assertShellLoaded(file: StaticString = #file, line: UInt = #line) {
        assertExists(app.tabBars.firstMatch, message: "Main tab bar should appear", file: file, line: line)
    }
}
