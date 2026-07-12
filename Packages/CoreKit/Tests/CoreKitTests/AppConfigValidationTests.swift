import Foundation
import Testing
@testable import CoreKit

struct ValidationScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let config: AppConfig
    let expectedIssue: ConfigurationIssue

    var testDescription: String { name }
}

@Suite("AppConfig validation")
struct AppConfigValidationTests {
    private static let appStoreID = "1234567890"

    private static func productionConfig(
        apiBaseURL: String = "https://api.tests.chapterflow.dev/app/api",
        cognitoRegion: String = "ca-central-1",
        cognitoUserPoolID: String = "ca-central-1_AbCdEf123",
        cognitoClientID: String = "a1b2c3d4e5f6g7h8i9j0k1l2m3",
        cognitoDomain: String = "auth.tests.chapterflow.dev",
        sentryDSN: String = "",
        storeKitMonthlyProductID: String = "com.chapterflow.tests.subscription.monthly",
        storeKitAnnualProductID: String = "com.chapterflow.tests.subscription.annual",
        storeKitAnnualUpfrontProductID: String = "",
        environment: AppEnvironment = .production,
        bundleIdentifier: String = AppConfig.expectedProductionBundleIdentifier,
        appStoreID: String = appStoreID,
        appStoreURL: String = "https://apps.apple.com/ca/app/chapterflow/id1234567890",
        supportURL: String = "https://support.tests.chapterflow.dev/help",
        sentryPolicy: SentryPolicy = .disabled,
        buildConfiguration: String = "Release",
        buildCommitSHA: String = "0123456789abcdef0123456789abcdef01234567",
        marketingVersion: String = "1.2.3",
        buildNumber: String = "42"
    ) -> AppConfig {
        AppConfig(
            apiBaseURL: apiBaseURL,
            cognitoRegion: cognitoRegion,
            cognitoUserPoolID: cognitoUserPoolID,
            cognitoClientID: cognitoClientID,
            cognitoDomain: cognitoDomain,
            sentryDSN: sentryDSN,
            storeKitMonthlyProductID: storeKitMonthlyProductID,
            storeKitAnnualProductID: storeKitAnnualProductID,
            storeKitAnnualUpfrontProductID: storeKitAnnualUpfrontProductID,
            environment: environment,
            bundleIdentifier: bundleIdentifier,
            appStoreID: appStoreID,
            appStoreURL: appStoreURL,
            supportURL: supportURL,
            sentryPolicy: sentryPolicy,
            buildConfiguration: buildConfiguration,
            buildCommitSHA: buildCommitSHA,
            marketingVersion: marketingVersion,
            buildNumber: buildNumber
        )
    }

    private static let invalidScenarios: [ValidationScenario] = [
        ValidationScenario(
            name: "missing API URL",
            config: productionConfig(apiBaseURL: ""),
            expectedIssue: ConfigurationIssue(field: .apiBaseURL, reason: .missing)
        ),
        ValidationScenario(
            name: "unexpanded API URL",
            config: productionConfig(apiBaseURL: "$(API_BASE_URL)"),
            expectedIssue: ConfigurationIssue(field: .apiBaseURL, reason: .unexpanded)
        ),
        ValidationScenario(
            name: "placeholder API URL",
            config: productionConfig(apiBaseURL: "https://api.example.com"),
            expectedIssue: ConfigurationIssue(field: .apiBaseURL, reason: .placeholder)
        ),
        ValidationScenario(
            name: "insecure production API URL",
            config: productionConfig(apiBaseURL: "http://api.tests.chapterflow.dev/app/api"),
            expectedIssue: ConfigurationIssue(field: .apiBaseURL, reason: .insecure)
        ),
        ValidationScenario(
            name: "local production API host",
            config: productionConfig(apiBaseURL: "https://localhost/app/api"),
            expectedIssue: ConfigurationIssue(field: .apiBaseURL, reason: .disallowedHost)
        ),
        ValidationScenario(
            name: "malformed Cognito region",
            config: productionConfig(cognitoRegion: "canada"),
            expectedIssue: ConfigurationIssue(field: .cognitoRegion, reason: .malformed)
        ),
        ValidationScenario(
            name: "Cognito pool does not match region",
            config: productionConfig(cognitoUserPoolID: "us-east-1_AbCdEf123"),
            expectedIssue: ConfigurationIssue(field: .cognitoUserPoolID, reason: .mismatch)
        ),
        ValidationScenario(
            name: "malformed Cognito client ID",
            config: productionConfig(cognitoClientID: "short"),
            expectedIssue: ConfigurationIssue(field: .cognitoClientID, reason: .malformed)
        ),
        ValidationScenario(
            name: "Cognito domain includes a scheme",
            config: productionConfig(cognitoDomain: "https://auth.tests.chapterflow.dev"),
            expectedIssue: ConfigurationIssue(field: .cognitoDomain, reason: .malformed)
        ),
        ValidationScenario(
            name: "wrong production bundle ID",
            config: productionConfig(bundleIdentifier: "com.chapterflow.tests.wrongbundle"),
            expectedIssue: ConfigurationIssue(field: .bundleIdentifier, reason: .mismatch)
        ),
        ValidationScenario(
            name: "malformed App Store ID",
            config: productionConfig(appStoreID: "id123"),
            expectedIssue: ConfigurationIssue(field: .appStoreID, reason: .malformed)
        ),
        ValidationScenario(
            name: "App Store ID cannot have a leading zero",
            config: productionConfig(
                appStoreID: "0123456789",
                appStoreURL: "https://apps.apple.com/app/id0123456789"
            ),
            expectedIssue: ConfigurationIssue(field: .appStoreID, reason: .malformed)
        ),
        ValidationScenario(
            name: "App Store URL is a search",
            config: productionConfig(appStoreURL: "https://apps.apple.com/search?term=ChapterFlow"),
            expectedIssue: ConfigurationIssue(field: .appStoreURL, reason: .malformed)
        ),
        ValidationScenario(
            name: "App Store URL points at another product",
            config: productionConfig(appStoreURL: "https://apps.apple.com/app/id9999999999"),
            expectedIssue: ConfigurationIssue(field: .appStoreURL, reason: .mismatch)
        ),
        ValidationScenario(
            name: "App Store URL contains mutable query data",
            config: productionConfig(
                appStoreURL: "https://apps.apple.com/app/id1234567890?campaign=release"
            ),
            expectedIssue: ConfigurationIssue(field: .appStoreURL, reason: .malformed)
        ),
        ValidationScenario(
            name: "App Store URL must end at the exact product identifier",
            config: productionConfig(
                appStoreURL: "https://apps.apple.com/app/id1234567890/reviews"
            ),
            expectedIssue: ConfigurationIssue(field: .appStoreURL, reason: .malformed)
        ),
        ValidationScenario(
            name: "App Store URL rejects an explicit port",
            config: productionConfig(
                appStoreURL: "https://apps.apple.com:443/app/id1234567890"
            ),
            expectedIssue: ConfigurationIssue(field: .appStoreURL, reason: .malformed)
        ),
        ValidationScenario(
            name: "support URL is not HTTPS",
            config: productionConfig(supportURL: "http://support.tests.chapterflow.dev/help"),
            expectedIssue: ConfigurationIssue(field: .supportURL, reason: .malformed)
        ),
        ValidationScenario(
            name: "missing monthly StoreKit product",
            config: productionConfig(storeKitMonthlyProductID: ""),
            expectedIssue: ConfigurationIssue(field: .storeKitMonthlyProductID, reason: .missing)
        ),
        ValidationScenario(
            name: "malformed annual StoreKit product",
            config: productionConfig(storeKitAnnualProductID: "annual"),
            expectedIssue: ConfigurationIssue(field: .storeKitAnnualProductID, reason: .malformed)
        ),
        ValidationScenario(
            name: "duplicate StoreKit products",
            config: productionConfig(
                storeKitAnnualProductID: "com.chapterflow.tests.subscription.monthly"
            ),
            expectedIssue: ConfigurationIssue(field: .storeKitAnnualProductID, reason: .duplicate)
        ),
        ValidationScenario(
            name: "production Sentry policy is unspecified",
            config: productionConfig(sentryPolicy: .unspecified),
            expectedIssue: ConfigurationIssue(field: .sentryPolicy, reason: .missing)
        ),
        ValidationScenario(
            name: "enabled Sentry has no DSN",
            config: productionConfig(sentryPolicy: .enabled),
            expectedIssue: ConfigurationIssue(field: .sentryDSN, reason: .missing)
        ),
        ValidationScenario(
            name: "enabled Sentry DSN cannot embed a secret",
            config: productionConfig(
                sentryDSN: "https://publickey:secret@sentry.tests.chapterflow.dev/456",
                sentryPolicy: .enabled
            ),
            expectedIssue: ConfigurationIssue(field: .sentryDSN, reason: .malformed)
        ),
        ValidationScenario(
            name: "disabled Sentry has a DSN",
            config: productionConfig(
                sentryDSN: "https://publickey@sentry.tests.chapterflow.dev/456",
                sentryPolicy: .disabled
            ),
            expectedIssue: ConfigurationIssue(field: .sentryDSN, reason: .inconsistent)
        ),
        ValidationScenario(
            name: "production commit is a placeholder",
            config: productionConfig(buildCommitSHA: "local"),
            expectedIssue: ConfigurationIssue(field: .buildCommitSHA, reason: .placeholder)
        ),
        ValidationScenario(
            name: "production commit is not a full SHA",
            config: productionConfig(buildCommitSHA: "deadbee"),
            expectedIssue: ConfigurationIssue(field: .buildCommitSHA, reason: .malformed)
        ),
        ValidationScenario(
            name: "production configuration is not Release",
            config: productionConfig(buildConfiguration: "Debug"),
            expectedIssue: ConfigurationIssue(field: .buildConfiguration, reason: .mismatch)
        ),
        ValidationScenario(
            name: "malformed marketing version",
            config: productionConfig(marketingVersion: "version-one"),
            expectedIssue: ConfigurationIssue(field: .marketingVersion, reason: .malformed)
        ),
        ValidationScenario(
            name: "production marketing version needs major and minor",
            config: productionConfig(marketingVersion: "1"),
            expectedIssue: ConfigurationIssue(field: .marketingVersion, reason: .malformed)
        ),
        ValidationScenario(
            name: "malformed build number",
            config: productionConfig(buildNumber: "build-42"),
            expectedIssue: ConfigurationIssue(field: .buildNumber, reason: .malformed)
        ),
        ValidationScenario(
            name: "production build number must be positive",
            config: productionConfig(buildNumber: "0"),
            expectedIssue: ConfigurationIssue(field: .buildNumber, reason: .malformed)
        )
    ]

    @Test("a complete production configuration is valid")
    func validProductionConfiguration() {
        let config = Self.productionConfig()

        #expect(config.configurationIssues.isEmpty)
        #expect(config.validate() == .valid(config: config, environment: .production))
    }

    @Test("repeated launch validation stays below the main-thread stall budget")
    func validationPerformanceBudget() {
        let config = Self.productionConfig()
        let duration = ContinuousClock().measure {
            for _ in 0..<25 {
                _ = config.configurationIssues
            }
        }

        #expect(duration < .milliseconds(250))
    }

    @Test("invalid production values emit their stable safe issue", arguments: invalidScenarios)
    func invalidProductionValues(_ scenario: ValidationScenario) {
        #expect(scenario.config.configurationIssues.contains(scenario.expectedIssue))
    }

    @Test("development allows local API and omits release-only values")
    func validDevelopmentConfiguration() {
        let config = AppConfig(
            apiBaseURL: "http://localhost:3000/app/api",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Development123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            cognitoDomain: "auth.dev.chapterflow.test",
            environment: .development
        )

        #expect(config.validate() == .valid(config: config, environment: .development))
    }

    @Test("staging may omit App Store, StoreKit, and provenance")
    func validStagingConfiguration() {
        let config = AppConfig(
            apiBaseURL: "https://api.staging.chapterflow.dev/app/api",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Staging123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            cognitoDomain: "auth.staging.chapterflow.dev",
            environment: .staging
        )

        #expect(config.validate() == .valid(config: config, environment: .staging))
    }

    @Test("environment must be explicit")
    func unknownEnvironmentIsInvalid() {
        let config = AppConfig(
            apiBaseURL: "https://api.development.chapterflow.dev/app/api",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Development123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            cognitoDomain: "auth.development.chapterflow.dev"
        )

        #expect(config.configurationIssues.contains(
            ConfigurationIssue(field: .environment, reason: .missing)
        ))
    }

    @Test("configured nonproduction App Store values must still form an exact pair")
    func partialOptionalAppStoreConfigurationIsInvalid() {
        let config = AppConfig(
            apiBaseURL: "https://api.staging.chapterflow.dev/app/api",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Staging123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            cognitoDomain: "auth.staging.chapterflow.dev",
            environment: .staging,
            appStoreID: Self.appStoreID
        )

        #expect(config.configurationIssues.contains(
            ConfigurationIssue(field: .appStoreURL, reason: .missing)
        ))
    }

    @Test("configured nonproduction StoreKit values require both recurring products")
    func partialOptionalStoreKitConfigurationIsInvalid() {
        let config = AppConfig(
            apiBaseURL: "https://api.staging.chapterflow.dev/app/api",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Staging123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            cognitoDomain: "auth.staging.chapterflow.dev",
            storeKitMonthlyProductID: "com.chapterflow.tests.subscription.monthly",
            environment: .staging
        )

        #expect(config.configurationIssues.contains(
            ConfigurationIssue(field: .storeKitAnnualProductID, reason: .missing)
        ))
    }

    @Test("annual upfront StoreKit product is rejected until backend support exists")
    func unsupportedAnnualUpfrontProductIsInvalid() {
        let config = Self.productionConfig(
            storeKitAnnualUpfrontProductID: "com.chapterflow.tests.subscription.upfront"
        )

        #expect(config.configurationIssues.contains(
            ConfigurationIssue(field: .storeKitAnnualUpfrontProductID, reason: .unsupported)
        ))
    }

    @Test("valid enabled Sentry policy and DSN are accepted")
    func enabledSentryConfiguration() {
        let config = Self.productionConfig(
            sentryDSN: "https://publickey@sentry.tests.chapterflow.dev/456",
            sentryPolicy: .enabled
        )

        #expect(config.configurationIssues.isEmpty)
        #expect(config.buildDiagnosticsRecord.sentryEnabled)
    }

    @Test(
        "approved exact App Store destinations are exposed",
        arguments: [
            "https://apps.apple.com/app/id1234567890",
            "https://apps.apple.com/app/id1234567890/",
            "https://apps.apple.com/ca/app/chapterflow/id1234567890",
            "itms-apps://itunes.apple.com/app/id1234567890"
        ]
    )
    func exactAppStoreDestinations(_ destination: String) {
        let config = Self.productionConfig(appStoreURL: destination)

        #expect(config.exactAppStoreURL?.absoluteString == destination)
    }

    @Test(
        "ambiguous App Store destinations are never exposed",
        arguments: [
            "https://apps.apple.com/search?term=ChapterFlow",
            "https://apps.apple.com/app/id1234567890?campaign=release",
            "https://apps.apple.com/app/id1234567890/reviews",
            "https://apps.apple.com:443/app/id1234567890",
            "https://apps.apple.com/app/id9999999999",
            "https://example.com/app/id1234567890",
            "http://apps.apple.com/app/id1234567890"
        ]
    )
    func rejectedAppStoreDestinations(_ destination: String) {
        let config = Self.productionConfig(appStoreURL: destination)

        #expect(config.exactAppStoreURL == nil)
    }

    @Test("support helper exposes only public HTTPS URLs")
    func supportURLHelper() {
        #expect(Self.productionConfig().supportURLValue?.host == "support.tests.chapterflow.dev")
        #expect(Self.productionConfig(supportURL: "http://support.tests.chapterflow.dev").supportURLValue == nil)
        #expect(Self.productionConfig(supportURL: "https://localhost/support").supportURLValue == nil)
    }

    @Test("Info.plist parsing reads every release field and debug alias")
    func infoValuesParsing() {
        let config = AppConfig.fromInfoValues([
            AppConfig.InfoKey.apiBaseURL: "http://localhost:3000/app/api",
            AppConfig.InfoKey.cognitoRegion: "ca-central-1",
            AppConfig.InfoKey.cognitoUserPoolID: "ca-central-1_Development123",
            AppConfig.InfoKey.cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3",
            AppConfig.InfoKey.cognitoDomain: "auth.dev.chapterflow.test",
            AppConfig.InfoKey.sentryDSN: "",
            AppConfig.InfoKey.storeKitMonthlyProductID: "com.chapterflow.tests.subscription.monthly",
            AppConfig.InfoKey.storeKitAnnualProductID: "com.chapterflow.tests.subscription.annual",
            AppConfig.InfoKey.storeKitAnnualUpfrontProductID: "",
            AppConfig.InfoKey.environment: "debug",
            AppConfig.InfoKey.bundleIdentifier: "com.chapterflow.ios.debug",
            AppConfig.InfoKey.appStoreID: Self.appStoreID,
            AppConfig.InfoKey.appStoreURL: "https://apps.apple.com/app/id1234567890",
            AppConfig.InfoKey.supportURL: "https://support.tests.chapterflow.dev/help",
            AppConfig.InfoKey.sentryPolicy: "disabled",
            AppConfig.InfoKey.buildConfiguration: "Debug",
            AppConfig.InfoKey.buildCommitSHA: "0123456789abcdef0123456789abcdef01234567",
            AppConfig.InfoKey.marketingVersion: "1.2.3",
            AppConfig.InfoKey.buildNumber: "42"
        ])

        #expect(config.environment == .development)
        #expect(config.sentryPolicy == .disabled)
        #expect(config.bundleIdentifier == "com.chapterflow.ios.debug")
        #expect(config.appStoreID == Self.appStoreID)
        #expect(config.buildCommitSHA == "0123456789abcdef0123456789abcdef01234567")
        #expect(config.configurationIssues.isEmpty)
    }

    @Test("Info.plist parse failures retain only safe issues")
    func infoValuesRejectInvalidEnums() {
        let config = AppConfig.fromInfoValues([
            AppConfig.InfoKey.environment: "$(CHAPTERFLOW_ENVIRONMENT)",
            AppConfig.InfoKey.sentryPolicy: "sometimes"
        ])

        #expect(config.sourceIssues == [
            ConfigurationIssue(field: .environment, reason: .unexpanded),
            ConfigurationIssue(field: .sentryPolicy, reason: .malformed)
        ])
        #expect(config.sourceIssues.map(\.code) == [
            "configuration.environment.unexpanded",
            "configuration.sentry_policy.malformed"
        ])
    }

    @Test("build diagnostics contain only the redacted allowlist")
    func diagnosticsAreRedacted() {
        let config = Self.productionConfig(
            sentryDSN: "https://publickey@sentry.tests.chapterflow.dev/456",
            storeKitAnnualUpfrontProductID: "com.chapterflow.tests.subscription.upfront",
            sentryPolicy: .enabled
        )
        let record = config.buildDiagnosticsRecord
        let labels = Set(Mirror(reflecting: record).children.compactMap(\.label))
        let reflected = String(reflecting: record)

        #expect(labels == [
            "environment", "apiHost", "bundleIdentifier", "marketingVersion",
            "buildNumber", "buildConfiguration", "buildCommitSHA",
            "storeKitProductCount", "sentryEnabled"
        ])
        #expect(record.apiHost == "api.tests.chapterflow.dev")
        #expect(record.storeKitProductCount == 3)
        #expect(!reflected.contains("/app/api"))
        #expect(!reflected.contains("com.chapterflow.tests.subscription.monthly"))
        #expect(!reflected.contains("publickey"))
    }

    @Test("issue code is stable and contains no rejected value")
    func issueCodeIsSafe() {
        let issue = ConfigurationIssue(field: .apiBaseURL, reason: .placeholder)

        #expect(issue.code == "configuration.api_base_url.placeholder")
        #expect(!issue.code.contains("example.com"))
    }

    @Test("legacy initializer remains source-compatible")
    func legacyInitializerDefaultsNewFields() {
        let config = AppConfig(
            apiBaseURL: "https://api.tests.chapterflow.dev",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Legacy123",
            cognitoClientID: "a1b2c3d4e5f6g7h8i9j0k1l2m3"
        )

        #expect(config.environment == .unknown)
        #expect(config.appStoreID.isEmpty)
        #expect(config.sentryPolicy == .unspecified)
        #expect(config.buildCommitSHA.isEmpty)
    }

    @Test("public configuration values satisfy Sendable boundaries")
    func publicTypesAreSendable() {
        requireSendable(AppEnvironment.production)
        requireSendable(SentryPolicy.disabled)
        requireSendable(ConfigurationIssue(field: .environment, reason: .missing))
        requireSendable(AppConfigurationState.unvalidated)
        requireSendable(Self.productionConfig().buildDiagnosticsRecord)
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
