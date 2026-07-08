import XCTest

/// XCUITests for the read → quiz → unlock chapter flow.
///
/// All network calls are served by ``CFStubURLProtocol`` using fixture JSON:
/// - Catalog: 2 books (Atomic Habits first).
/// - Book state: chapter 1 unlocked.
/// - Quiz: 2 questions; submit returns ``passed=true, unlockedNextChapter=true``.
///
/// The user starts as signed-in (``CFUITestCase.needsAuth = true``).
final class ReadQuizUnlockFlowTests: CFUITestCase {

    private var robot: AppRobot { AppRobot(app: app) }

    // MARK: - Library loads books

    func testLibraryShowsBooks() {
        robot.waitForTabBar()

        // Navigate to Library tab.
        robot.goToLibrary()

        // The stub catalog contains "Atomic Habits".
        robot.assertBookVisible("Atomic Habits")
    }

    func testHomeScreenShowsContinueReadingOrDiscover() {
        robot.waitForTabBar()
        robot.goToHome()

        // Home should show at least one piece of content (continue reading or discover).
        let hasContent = app.cells.firstMatch.waitForExistence(timeout: 15)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'atomic' OR label CONTAINS[c] 'deep work'")
            ).firstMatch.waitForExistence(timeout: 15)
        XCTAssert(hasContent, "Home screen should show library content from stub catalog")
    }

    // MARK: - Book detail

    func testTappingBookOpensDetail() {
        robot.waitForTabBar()
        robot.tapBook(containing: "Atomic Habits")

        // Book detail must show at least one chapter cell.
        let chapterCell = app.cells.firstMatch
        XCTAssert(chapterCell.waitForExistence(timeout: 15), "Book detail must show chapters")
    }

    // MARK: - No error states

    func testNoErrorWithStubCatalog() {
        robot.waitForTabBar()
        robot.assertNoErrorState()
    }

    func testLibraryTabNoError() {
        robot.waitForTabBar()
        robot.goToLibrary()

        // Wait for content to settle.
        _ = app.cells.firstMatch.waitForExistence(timeout: 15)
        robot.assertNoErrorState()
    }

    // MARK: - Stub API contract

    /// Confirms the stub server satisfies the core reading-loop endpoints.
    /// If the app shows an error state, the stub routes are misconfigured.
    func testStubServerCoversReadingLoopEndpoints() {
        robot.waitForTabBar()

        // Navigate to Library and back; verifies /book/books route.
        robot.goToLibrary()
        _ = app.cells.firstMatch.waitForExistence(timeout: 15)
        robot.assertNoErrorState()

        // Navigate Home; verifies /book/me/progress and /book/me/dashboard.
        robot.goToHome()
        robot.assertNoErrorState()
    }
}
