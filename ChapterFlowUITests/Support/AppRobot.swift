import XCTest

/// Robot-pattern helpers for navigating the ChapterFlow XCUITest suite.
///
/// Each method performs a navigation action or assertion and returns `self`
/// to support call-chaining. All waits use generous timeouts to handle
/// stub-server latency on CI runners.
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
    func goToSettings() -> Self {
        tap(tab: "setting")
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
        let match = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", substring)
        ).firstMatch
        if match.waitForExistence(timeout: 12) { match.tap() }
        return self
    }

    @discardableResult
    func waitForTabBar(timeout: TimeInterval = 20) -> Self {
        _ = app.tabBars.firstMatch.waitForExistence(timeout: timeout)
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

    func assertBookVisible(_ title: String, file: StaticString = #file, line: UInt = #line) {
        let book = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssert(book.waitForExistence(timeout: 15), "Book '\(title)' should be visible", file: file, line: line)
    }

    // MARK: - Private

    private func tap(tab keyword: String) {
        let button = app.tabBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", keyword)
        ).firstMatch
        if button.waitForExistence(timeout: 10) { button.tap() }
    }
}
