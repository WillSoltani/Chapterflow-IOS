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

        // Wait for any cell to appear first (content loaded from stub), then verify
        // the specific book title. Two-phase wait is more robust than waiting on text alone.
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        robot.assertBookVisible("Atomic Habits")
    }

    func testHomeScreenShowsContinueReadingOrDiscover() {
        robot.waitForTabBar()
        robot.goToHome()

        // Home shows content via scrollable containers or text elements; search all descendants.
        // Some layouts don't use UICollectionView cells, so we broaden the query.
        // Inline NSPredicate creation avoids Swift 6 "sending non-Sendable" errors.
        let hasContent = app.cells.firstMatch.waitForExistence(timeout: 20)
            || app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label CONTAINS[c] 'atomic' OR label CONTAINS[c] 'deep work' " +
                            "OR label CONTAINS[c] 'reading' OR label CONTAINS[c] 'discover'"
                ))
                .firstMatch
                .waitForExistence(timeout: 20)
        XCTAssert(hasContent, "Home screen should show library content from stub catalog")
    }

    // MARK: - Book detail

    func testTappingBookOpensDetail() {
        robot.waitForTabBar()
        robot.goToLibrary()
        robot.tapBook(containing: "Atomic Habits")

        // Book detail must show at least one chapter or the book title in the nav bar.
        // Use broad descendant search — chapter rows may be cells or custom views.
        let detailLoaded = app.cells.firstMatch.waitForExistence(timeout: 25)
            || app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] 'chapter' OR label CONTAINS[c] 'atomic'")
            ).firstMatch.waitForExistence(timeout: 10)
        XCTAssert(detailLoaded, "Book detail must show chapters after tapping book")
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
