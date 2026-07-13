import XCTest

/// Robot-pattern helpers for navigating the ChapterFlow XCUITest suite.
///
/// Each method performs a navigation action or assertion and returns `self`
/// to support call-chaining. All waits use generous timeouts to handle
/// stub-server latency on CI runners.
// XCTest always dispatches UI interaction on the main thread, so no actor
// annotation is needed here despite XCUIElement being @MainActor in Xcode 26.
struct AppRobot {
    let app: XCUIApplication

    // MARK: - Tab navigation

    @discardableResult
    func goToHome() -> Self {
        tap(tab: "home")
        return self
    }

    @discardableResult
    func goToLibrary() -> Self {
        tap(tab: "librar")
        return self
    }

    @discardableResult
    func goToSettings(file: StaticString = #file, line: UInt = #line) -> Self {
        let settingsTab = app.tabBars.buttons["Settings"]
        let settingsTabExists = settingsTab.waitForExistence(timeout: 10)
        XCTAssertTrue(
            settingsTabExists,
            "Settings tab should exist before navigation",
            file: file,
            line: line
        )
        guard settingsTabExists else { return self }

        settingsTab.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 15),
            "Settings navigation destination should be visible after tapping its tab",
            file: file,
            line: line
        )
        return self
    }

    @discardableResult
    func goToReviews() -> Self {
        tap(tab: "review")
        return self
    }

    // MARK: - Content interactions

    @discardableResult
    func tapBook(containing substring: String) -> Self {
        // Search all accessibility elements — book titles can be in staticTexts, buttons,
        // or NavigationLink labels depending on the list implementation.
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", substring)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        if match.waitForExistence(timeout: 30) { match.tap() }
        return self
    }

    @discardableResult
    func waitForTabBar(
        timeout: TimeInterval = 20,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Self {
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: timeout),
            "Tab bar should be visible",
            file: file,
            line: line
        )
        return self
    }

    // MARK: - Assertions

    func assertTabBarVisible(file: StaticString = #file, line: UInt = #line) {
        XCTAssert(
            app.tabBars.firstMatch.waitForExistence(timeout: 20),
            "Tab bar should be visible",
            file: file, line: line
        )
    }

    func assertNoErrorState(file: StaticString = #file, line: UInt = #line) {
        // Give the UI a moment to settle before checking for error states.
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
        XCTAssertFalse(
            app.staticTexts["Something went wrong"].exists,
            "Should not show an error state",
            file: file, line: line
        )
    }

    // MARK: - Private

    private func tap(tab keyword: String) {
        let button = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", keyword)
        ).firstMatch
        if button.waitForExistence(timeout: 10) { button.tap() }
    }
}
