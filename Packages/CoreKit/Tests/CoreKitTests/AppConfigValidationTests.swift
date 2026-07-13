import Foundation
import Testing
@testable import CoreKit

@Suite("Development app configuration validation")
struct AppConfigValidationTests {
    @Test("valid API and Cognito configuration is capability-wrapped")
    func validConfiguration() throws {
        let config = validConfig()
        let result = config.validate()

        guard case .valid(let validated) = result else {
            Issue.record("Expected valid configuration, got \(result)")
            return
        }
        #expect(validated.value == config)
    }

    @Test("valid required values are trimmed before service construction")
    func validValuesAreNormalized() {
        let config = AppConfig(
            apiBaseURL: "  https://api.chapterflow.test/v1  ",
            cognitoRegion: " us-east-1 ",
            cognitoUserPoolID: " us-east-1_ChapterFlowTest ",
            cognitoClientID: " chapterflowclient1234567890 ",
            cognitoDomain: " auth.chapterflow.test "
        )

        guard case .valid(let validated) = config.validate() else {
            Issue.record("Whitespace around otherwise valid values should be normalized")
            return
        }
        #expect(validated.value.apiBaseURL == "https://api.chapterflow.test/v1")
        #expect(validated.value.cognitoRegion == "us-east-1")
        #expect(validated.value.cognitoUserPoolID == "us-east-1_ChapterFlowTest")
        #expect(validated.value.cognitoClientID == "chapterflowclient1234567890")
        #expect(validated.value.cognitoDomain == "auth.chapterflow.test")
    }

    @Test("absent Info.plist fields are reported as missing in stable field order")
    func missingFields() {
        let result = AppConfig.fromInfoValues([:]).validate()

        #expect(result == .invalid([
            issue(.apiBaseURL, .missing),
            issue(.cognitoRegion, .missing),
            issue(.cognitoUserPoolID, .missing),
            issue(.cognitoClientID, .missing),
            issue(.cognitoDomain, .missing),
        ]))
    }

    @Test("present whitespace-only fields are empty rather than missing")
    func emptyFields() {
        let values = Dictionary(
            uniqueKeysWithValues: requiredInfoKeys.map { ($0, "  \n") }
        )

        #expect(AppConfig.fromInfoValues(values).configurationIssues == [
            issue(.apiBaseURL, .empty),
            issue(.cognitoRegion, .empty),
            issue(.cognitoUserPoolID, .empty),
            issue(.cognitoClientID, .empty),
            issue(.cognitoDomain, .empty),
        ])
    }

    @Test(
        "malformed field shapes are categorized safely",
        arguments: [
            (AppConfigurationField.apiBaseURL, "not a URL"),
            (.cognitoRegion, "east-1"),
            (.cognitoUserPoolID, "us-east-1/nope"),
            (.cognitoClientID, "short"),
            (.cognitoDomain, "https://auth.chapterflow.test/path"),
        ]
    )
    func malformedFields(field: AppConfigurationField, value: String) {
        let config = replacing(field, with: value)

        #expect(config.configurationIssues.contains(issue(field, .malformed)))
    }

    @Test("the committed example values are rejected as template or X-filled placeholders")
    func exampleValuesAreInvalid() {
        let config = AppConfig(
            apiBaseURL: "https://api.chapterflow.example.com",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_XXXXXXXXX",
            cognitoClientID: "XXXXXXXXXXXXXXXXXXXXXXXXXX",
            cognitoDomain: "auth.your-domain.auth.us-east-1.amazoncognito.com"
        )

        #expect(config.configurationIssues == [
            issue(.apiBaseURL, .templateValue),
            issue(.cognitoUserPoolID, .placeholder),
            issue(.cognitoClientID, .placeholder),
            issue(.cognitoDomain, .templateValue),
        ])
    }

    @Test("unexpanded build settings are distinct from empty and malformed values")
    func unexpandedValues() {
        let config = replacing(.apiBaseURL, with: "$(API_BASE_URL)")

        #expect(config.configurationIssues == [issue(.apiBaseURL, .unexpanded)])
    }

    @Test(
        "API transport and URL rules are deterministic",
        arguments: [
            ("https://api.chapterflow.test", Optional<AppConfigurationIssueCategory>.none),
            ("http://localhost:8080", Optional<AppConfigurationIssueCategory>.none),
            ("http://127.0.0.1:8080", Optional<AppConfigurationIssueCategory>.none),
            ("http://api.chapterflow.test", .some(.insecureTransport)),
            ("ftp://api.chapterflow.test", .some(.malformed)),
            ("https://user:password@api.chapterflow.test", .some(.malformed)),
            ("https://api.chapterflow.test?token=private", .some(.malformed)),
        ]
    )
    func apiURLRules(value: String, expected: AppConfigurationIssueCategory?) {
        let issues = replacing(.apiBaseURL, with: value).configurationIssues

        if let expected {
            #expect(issues == [issue(.apiBaseURL, expected)])
        } else {
            #expect(issues.isEmpty)
        }
    }

    @Test("Cognito pool region must agree with the configured region")
    func poolRegionMismatch() {
        let config = replacing(.cognitoUserPoolID, with: "ca-central-1_ChapterFlowTest")

        #expect(config.configurationIssues == [issue(.cognitoUserPoolID, .regionMismatch)])
    }

    @Test("standard Cognito hosted domain agrees with the configured region")
    func hostedDomainRegionMatches() {
        let config = replacing(
            .cognitoDomain,
            with: "chapterflow-dev.auth.us-east-1.amazoncognito.com"
        )

        #expect(config.configurationIssues.isEmpty)
    }

    @Test("standard Cognito hosted domain must agree with the configured region")
    func hostedDomainRegionMismatch() {
        let config = replacing(
            .cognitoDomain,
            with: "chapterflow-dev.auth.ca-central-1.amazoncognito.com"
        )

        #expect(config.configurationIssues == [issue(.cognitoDomain, .regionMismatch)])
    }

    @Test(
        "valid custom Cognito domains do not require an inferable region",
        arguments: ["auth.chapterflow.ca", "auth.chapterflow.test"]
    )
    func customDomainsRemainValid(_ domain: String) {
        #expect(replacing(.cognitoDomain, with: domain).configurationIssues.isEmpty)
    }

    @Test(
        "AWS Cognito hosted-domain lookalikes remain malformed",
        arguments: [
            "amazoncognito.com",
            "auth.us-east-1.amazoncognito.com",
            "chapterflow.us-east-1.amazoncognito.com",
            "chapterflow.auth.east-1.amazoncognito.com",
            "chapterflow.dev.auth.us-east-1.amazoncognito.com",
        ]
    )
    func malformedHostedDomains(_ domain: String) {
        #expect(
            replacing(.cognitoDomain, with: domain).configurationIssues == [
                issue(.cognitoDomain, .malformed),
            ]
        )
    }

    @Test("invalid outcomes and issue codes retain no private configuration values")
    func invalidOutcomeIsRedacted() {
        let privateURL = "https://private.internal.test/path/to/account"
        let privatePool = "ca-central-1_PrivatePoolIdentifier"
        let privateClient = "privateclientidentifier123456"
        let privateDomain = "private-prefix.auth.us-west-2.amazoncognito.com"
        let config = AppConfig(
            apiBaseURL: "\(privateURL)?credential=do-not-log",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: privatePool,
            cognitoClientID: privateClient,
            cognitoDomain: privateDomain
        )
        let result = config.validate()
        let reflected = String(reflecting: result)

        #expect(!reflected.contains(privateURL))
        #expect(!reflected.contains(privatePool))
        #expect(!reflected.contains(privateClient))
        #expect(!reflected.contains(privateDomain))
        #expect(!reflected.contains("credential"))
        #expect(config.configurationIssues.map(\.code) == [
            "configuration.api_base_url.malformed",
            "configuration.cognito_domain.region_mismatch",
        ])

        let record = AppConfigurationDiagnosticRecord(
            status: .invalid,
            buildConfiguration: .debug,
            issues: config.configurationIssues,
            liveServicesConstructed: false
        )
        #expect(!String(reflecting: record).contains(privateDomain))
    }

    @Test("diagnostic records expose only safe categories and readiness")
    func diagnosticRecordIsRedacted() {
        let record = AppConfigurationDiagnosticRecord(
            status: .invalid,
            buildConfiguration: .debug,
            issues: [issue(.cognitoClientID, .placeholder)],
            liveServicesConstructed: false
        )
        let labels = Set(Mirror(reflecting: record).children.compactMap(\.label))
        let reflected = String(reflecting: record)

        #expect(labels == [
            "status", "buildConfiguration", "issues",
            "liveServicesConstructed", "supportCode",
        ])
        #expect(record.supportCode == "CF-DEV-CFG-001")
        #expect(!reflected.contains("https://"))
        #expect(!reflected.contains("PrivatePoolIdentifier"))
    }

    private var requiredInfoKeys: [String] {
        [
            AppConfig.InfoKey.apiBaseURL,
            AppConfig.InfoKey.cognitoRegion,
            AppConfig.InfoKey.cognitoUserPoolID,
            AppConfig.InfoKey.cognitoClientID,
            AppConfig.InfoKey.cognitoDomain,
        ]
    }

    private func validConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.test/v1",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_ChapterFlowTest",
            cognitoClientID: "chapterflowclient1234567890",
            cognitoDomain: "auth.chapterflow.test"
        )
    }

    private func replacing(_ field: AppConfigurationField, with value: String) -> AppConfig {
        let valid = validConfig()
        return AppConfig(
            apiBaseURL: field == .apiBaseURL ? value : valid.apiBaseURL,
            cognitoRegion: field == .cognitoRegion ? value : valid.cognitoRegion,
            cognitoUserPoolID: field == .cognitoUserPoolID ? value : valid.cognitoUserPoolID,
            cognitoClientID: field == .cognitoClientID ? value : valid.cognitoClientID,
            cognitoDomain: field == .cognitoDomain ? value : valid.cognitoDomain
        )
    }

    private func issue(
        _ field: AppConfigurationField,
        _ category: AppConfigurationIssueCategory
    ) -> AppConfigurationIssue {
        AppConfigurationIssue(field: field, category: category)
    }
}
