import XCTest

// MARK: - Environment keys

/// Environment variable keys used by the XCUITest stub infrastructure.
/// Set these in ``XCUIApplication.launchEnvironment`` before calling ``launch()``.
enum TestEnv {
    /// Set to "1" to register ``CFStubURLProtocol`` and serve fixture JSON for all requests.
    static let stubServer  = "CF_STUB_SERVER"
    /// Set to "1" to seed the Keychain with a test JWT (bypasses real Cognito auth).
    static let bypassAuth  = "CF_UITEST_BYPASS_AUTH"
    /// Set to "1" to enable the optional smoke lane (hits real prod API, non-blocking).
    static let realAPI     = "CF_REAL_API"
    /// A real id_token for the smoke lane (injected via CI secrets).
    static let apiToken    = "CF_API_TOKEN"
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

    /// Return `true` (default) to launch with a pre-seeded test session.
    /// Return `false` to start the app in the unauthenticated state.
    var needsAuth: Bool { true }

    /// Additional launch-environment entries applied before ``app.launch()``.
    var extraLaunchEnvironment: [String: String] { [:] }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment[TestEnv.stubServer] = "1"
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
