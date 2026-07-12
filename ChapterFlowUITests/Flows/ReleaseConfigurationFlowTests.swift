import XCTest

/// Deterministic coverage for WP-REL-01's two user-visible launch gates.
///
/// These tests run against the real app composition with fixture networking.
/// The launch seams are DEBUG-only and still exercise the production validators.
final class ForceUpdateConfigurationFlowTests: CFUITestCase {
    @MainActor
    func testHardGateExposesExactUpdateAndSupportActions() {
        app.terminate()
        app.launchArguments = ["--demo-tab-shell", "--config-gate=hard"]
        app.launch()

        assertExists(
            app.staticTexts["Update Required"],
            message: "The hard force-update gate should present a clear heading"
        )

        // This action is rendered only when AppConfigService accepts the compiled
        // numeric App Store ID and the product URL contains that exact ID.
        let updateAction = app.buttons["Update ChapterFlow on the App Store"]
        assertExists(
            updateAction,
            message: "A validated product-specific App Store action should be available"
        )
        let updateActionIsEnabled = updateAction.isEnabled
        XCTAssertTrue(updateActionIsEnabled, "The exact App Store action should be enabled")
        assertHittable(
            updateAction,
            message: "The exact App Store action should be reachable after presentation"
        )

        // SwiftUI Link is exposed as a button on some OS releases and as a link
        // on others, so resolve the same stable label across actionable types.
        let supportButton = app.buttons["Contact Support"]
        let supportAction = supportButton.waitForExistence(timeout: 2)
            ? supportButton
            : app.links["Contact Support"]
        assertExists(
            supportAction,
            message: "A support recovery action should remain available beside Update"
        )
        let supportActionIsEnabled = supportAction.isEnabled
        XCTAssertTrue(supportActionIsEnabled, "The support recovery action should be enabled")
        assertHittable(
            supportAction,
            message: "The support recovery action should be reachable after presentation"
        )
    }
}

final class InvalidBootstrapConfigurationFlowTests: CFUITestCase {
    override var needsAuth: Bool { false }

    override var extraLaunchEnvironment: [String: String] {
        [TestEnv.invalidConfiguration: "1"]
    }

    @MainActor
    func testInvalidConfigurationFailsClosedBeforeAppShellConstruction() {
        let failureSurface = app.descendants(matching: .any)["app-configuration-failure"]
        assertExists(
            failureSurface,
            message: "Invalid configuration should render the explicit bootstrap failure surface"
        )
        assertExists(app.staticTexts["ChapterFlow Can't Start"])
        assertExists(app.staticTexts["Support code: CF-CFG-001"])
        assertExists(app.buttons["Contact Support"])

        let didExposeAppShell = app.tabBars.firstMatch.waitForExistence(timeout: 2)
        XCTAssertFalse(
            didExposeAppShell,
            "Invalid configuration must not construct or expose the app shell"
        )
    }
}
