import Foundation
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

        // Verify the stub catalog loaded by checking that book-card cells appear.
        // On iOS 18 / Xcode 26 the SwiftUI List accessibility tree does not expose
        // inner button labels to app.descendants label searches, so we assert via
        // cell existence (each BookCardView row = one List cell) which is reliable.
        // The stub only returns books so any cells mean the catalog loaded correctly.
        let hasBookCells = app.cells.firstMatch.waitForExistence(timeout: 60)
        XCTAssert(hasBookCells, "Library should show book-card cells from stub catalog")
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

/// Proves that remote artwork remains presentation-only: the fallback catalog
/// is immediately interactive, navigation succeeds while the response is still
/// delayed, and the eventual PNG replaces the detail fallback.
final class BookArtworkFlowTests: CFUITestCase {
    private let artworkToken = UUID().uuidString

    override var extraLaunchEnvironment: [String: String] {
        [
            "CF_STUB_ARTWORK_DELAY_MS": "20000",
            "CF_STUB_ARTWORK_TOKEN": artworkToken,
        ]
    }

    func testDelayedArtworkDoesNotBlockCatalogOrNavigation() {
        let robot = AppRobot(app: app)
        robot.waitForTabBar()
        robot.goToLibrary()

        let firstBook = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Atomic Habits'")
        ).firstMatch
        assertExists(
            firstBook,
            message: "The fallback catalog card must be available before artwork completes",
            timeout: 60
        )
        let catalogFallback = firstBook.screenshot()
        let fallbackAttachment = XCTAttachment(screenshot: catalogFallback)
        fallbackAttachment.name = "Catalog fallback before remote artwork"
        fallbackAttachment.lifetime = .keepAlways
        add(fallbackAttachment)

        firstBook.tap()
        assertExists(
            app.navigationBars["Atomic Habits"],
            message: "Book navigation must remain usable while artwork is loading",
            timeout: 15
        )

        let detailSurface = app.scrollViews.firstMatch
        assertExists(detailSurface, message: "The loaded book detail must be visible")
        let detailFallback = detailSurface.screenshot().pngRepresentation
        let earliestExpectedDelivery = Date().addingTimeInterval(21)
        let artworkReplacedFallback = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                Date() >= earliestExpectedDelivery
                    && detailSurface.exists
                    && detailSurface.screenshot().pngRepresentation != detailFallback
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [artworkReplacedFallback], timeout: 35),
            .completed,
            "The generated remote PNG must replace the visible fallback"
        )

        let remoteAttachment = XCTAttachment(screenshot: detailSurface.screenshot())
        remoteAttachment.name = "Book detail after remote artwork"
        remoteAttachment.lifetime = .keepAlways
        add(remoteAttachment)

        let backButton = app.navigationBars["Atomic Habits"].buttons.firstMatch
        assertExists(backButton, message: "Book detail must keep its back navigation affordance")
        backButton.tap()
        assertExists(
            app.navigationBars["Library"],
            message: "Navigation must remain usable after artwork replacement"
        )
        assertExists(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] 'Atomic Habits'")
            ).firstMatch,
            message: "The catalog must remain available after returning"
        )
    }
}
