import Testing
import CoreKit
@testable import AppFeature

@Suite("Configured app root")
struct ConfiguredAppRootViewTests {
    @Test("unvalidated configuration stays in the validating route")
    func unvalidatedRoute() {
        #expect(AppBootstrapRoute(state: .unvalidated) == .validating)
    }

    @Test("valid configuration is the only route that constructs the application")
    func validRoute() {
        let config = validConfig()
        #expect(
            AppBootstrapRoute(state: .valid(config: config, environment: .development))
                == .application(config)
        )
    }

    @Test("invalid configuration routes to a failure surface")
    func invalidRoute() {
        let config = validConfig()
        let issues = [ConfigurationIssue(field: .appStoreID, reason: .missing)]
        #expect(
            AppBootstrapRoute(state: .invalid(config: config, issues: issues))
                == .configurationFailure(config: config, issues: issues)
        )
    }

    @Test("internal issue codes fail closed for production and unknown environments")
    func diagnosticVisibility() {
        let issues = [ConfigurationIssue(field: .apiBaseURL, reason: .missing)]

        #expect(ConfigurationIssueVisibility.visibleCodes(
            environment: .development,
            issues: issues
        ) == ["configuration.api_base_url.missing"])
        #expect(ConfigurationIssueVisibility.visibleCodes(
            environment: .staging,
            issues: issues
        ) == ["configuration.api_base_url.missing"])
        #expect(ConfigurationIssueVisibility.visibleCodes(
            environment: .production,
            issues: issues
        ).isEmpty)
        #expect(ConfigurationIssueVisibility.visibleCodes(
            environment: .unknown,
            issues: issues
        ).isEmpty)
    }

    @Test("launch diagnostics are emitted once and seed internal StoreKit status")
    @MainActor
    func launchDiagnosticsWiring() async {
        let model = AppModel(config: validConfig())

        await model.emitLaunchConfigurationDiagnostic()
        await model.emitLaunchConfigurationDiagnostic()

        let record = await model.appConfigurationDiagnostics.latestStoreKitDiagnostics()
        #expect(record?.configuredProductCount == 0)
        #expect(record?.loadedProductCount == 0)
        #expect(record?.configuredProductIDs.isEmpty == true)
        #expect(record?.loadedProductIDs.isEmpty == true)
        #expect(record?.verificationEndpointHealth == .notChecked)
    }

    private func validConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.test",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_test",
            cognitoClientID: "TestClient123",
            cognitoDomain: "auth.chapterflow.test",
            environment: .development
        )
    }
}
