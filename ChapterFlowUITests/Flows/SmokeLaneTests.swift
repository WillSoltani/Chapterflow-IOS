import XCTest

/// Optional smoke lane that hits the REAL ChapterFlow API.
///
/// These tests are **non-blocking**: they are skipped automatically unless
/// ``CF_REAL_API=1`` is set in the environment.  They are NOT required for
/// PR merge and do NOT run in the standard CI build.
///
/// ## Usage
/// ```bash
/// CF_REAL_API=1 CF_API_TOKEN=<your_id_token> \
///   xcodebuild test \
///     -project ChapterFlow.xcodeproj \
///     -scheme ChapterFlow \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     -only-testing:ChapterFlowUITests/SmokeLaneTests
/// ```
///
/// ``CF_API_TOKEN`` is your Cognito ``id_token`` obtained from the browser
/// DevTools (Application → Storage → Cookies → ``id_token``).
final class SmokeLaneTests: XCTestCase {

    // MARK: - Guard

    private func requireRealAPI() throws {
        guard ProcessInfo.processInfo.environment[TestEnv.realAPI] == "1" else {
            throw XCTSkip("Smoke lane disabled. Set CF_REAL_API=1 to run against the real API.")
        }
    }

    // MARK: - Tests

    func testRealAPISessionEndpoint() throws {
        try requireRealAPI()

        let app = XCUIApplication()
        // Bypass auth via seeded token; do NOT enable the stub server.
        if let token = ProcessInfo.processInfo.environment[TestEnv.apiToken], !token.isEmpty {
            app.launchEnvironment[TestEnv.bypassAuth] = "1"
        }
        app.launch()
        defer { app.terminate() }

        let tabBar = app.tabBars.firstMatch
        XCTAssert(tabBar.waitForExistence(timeout: 30),
                  "Real API smoke: main shell should appear within 30 s")
    }

    func testRealCatalogLoads() throws {
        try requireRealAPI()

        let app = XCUIApplication()
        app.launchEnvironment[TestEnv.bypassAuth] = "1"
        app.launch()
        defer { app.terminate() }

        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)

        // Navigate to Library and verify at least one book card loads.
        let libraryTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'librar'")
        ).firstMatch
        if libraryTab.waitForExistence(timeout: 5) { libraryTab.tap() }

        let cell = app.cells.firstMatch
        XCTAssert(cell.waitForExistence(timeout: 30),
                  "Real API smoke: library catalog should load at least one book")
    }
}
