import XCTest

/// Optional smoke lane that hits the REAL ChapterFlow API.
///
/// These tests are **non-blocking**: they are skipped automatically unless
/// ``CF_REAL_API=1`` is set in the environment.  They are NOT required for
/// PR merge and do NOT run in the standard CI build.
///
/// ## Usage
/// ```bash
/// CF_REAL_API=1 \
///   xcodebuild test \
///     -project ChapterFlow.xcodeproj \
///     -scheme ChapterFlow \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     -only-testing:ChapterFlowUITests/SmokeLaneTests
/// ```
final class SmokeLaneTests: XCTestCase {

    // MARK: - Guard

    private func requireRealAPI() throws {
        guard ProcessInfo.processInfo.environment[TestEnv.realAPI] == "1" else {
            throw XCTSkip("Smoke lane disabled. Set CF_REAL_API=1 to run against the real API.")
        }
    }

    // MARK: - Tests

    func testRealAPIGuestShell() throws {
        try requireRealAPI()

        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        enterGuestMode(in: app)
    }

    func testRealCatalogLoads() throws {
        try requireRealAPI()

        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        enterGuestMode(in: app)

        // Navigate to Library and verify at least one book card loads.
        let libraryTab = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'librar'")
        ).firstMatch
        if libraryTab.waitForExistence(timeout: 5) { libraryTab.tap() }

        let cell = app.cells.firstMatch
        XCTAssert(cell.waitForExistence(timeout: 30),
                  "Real API smoke: library catalog should load at least one book")
    }

    private func enterGuestMode(in app: XCUIApplication) {
        let browse = app.buttons["Continue browsing without creating an account"]
        XCTAssertTrue(browse.waitForExistence(timeout: 30), "Real API smoke must begin from signed-out UI")
        browse.tap()
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 30),
            "Real API smoke: guest shell should appear within 30 seconds"
        )
    }
}
