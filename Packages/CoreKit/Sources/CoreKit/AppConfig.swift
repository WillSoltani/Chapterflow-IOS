import Foundation

/// Strongly typed application configuration populated from build-setting values
/// embedded in the app's `Info.plist`.
public struct AppConfig: Sendable, Equatable {
    public static let expectedProductionBundleIdentifier = "com.chapterflow.ios"

    public let apiBaseURL: String
    public let cognitoRegion: String
    public let cognitoUserPoolID: String
    public let cognitoClientID: String
    /// Custom Cognito domain, e.g. `auth.chapterflow.ca` (no scheme or trailing slash).
    public let cognitoDomain: String
    /// Sentry DSN. An empty value is valid only when the configured policy does not enable Sentry.
    public let sentryDSN: String

    // MARK: - StoreKit 2 product IDs

    public let storeKitMonthlyProductID: String
    public let storeKitAnnualProductID: String
    public let storeKitAnnualUpfrontProductID: String

    // MARK: - Environment and release identity

    public let environment: AppEnvironment
    public let bundleIdentifier: String
    public let appStoreID: String
    public let appStoreURL: String
    public let supportURL: String
    public let sentryPolicy: SentryPolicy
    public let buildConfiguration: String
    public let buildCommitSHA: String
    public let marketingVersion: String
    public let buildNumber: String

    /// Safe parse failures captured while converting untyped `Info.plist` values.
    /// Raw configuration values are deliberately never retained in an issue.
    let sourceIssues: [ConfigurationIssue]

    /// Existing call sites remain source-compatible because every newly added
    /// release field has a conservative default.
    public init(
        apiBaseURL: String,
        cognitoRegion: String,
        cognitoUserPoolID: String,
        cognitoClientID: String,
        cognitoDomain: String = "",
        sentryDSN: String = "",
        storeKitMonthlyProductID: String = "",
        storeKitAnnualProductID: String = "",
        storeKitAnnualUpfrontProductID: String = "",
        environment: AppEnvironment = .unknown,
        bundleIdentifier: String = "",
        appStoreID: String = "",
        appStoreURL: String = "",
        supportURL: String = "",
        sentryPolicy: SentryPolicy = .unspecified,
        buildConfiguration: String = "",
        buildCommitSHA: String = "",
        marketingVersion: String = "",
        buildNumber: String = ""
    ) {
        self.init(
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
            buildNumber: buildNumber,
            sourceIssues: []
        )
    }

    private init(
        apiBaseURL: String,
        cognitoRegion: String,
        cognitoUserPoolID: String,
        cognitoClientID: String,
        cognitoDomain: String,
        sentryDSN: String,
        storeKitMonthlyProductID: String,
        storeKitAnnualProductID: String,
        storeKitAnnualUpfrontProductID: String,
        environment: AppEnvironment,
        bundleIdentifier: String,
        appStoreID: String,
        appStoreURL: String,
        supportURL: String,
        sentryPolicy: SentryPolicy,
        buildConfiguration: String,
        buildCommitSHA: String,
        marketingVersion: String,
        buildNumber: String,
        sourceIssues: [ConfigurationIssue]
    ) {
        self.apiBaseURL = apiBaseURL
        self.cognitoRegion = cognitoRegion
        self.cognitoUserPoolID = cognitoUserPoolID
        self.cognitoClientID = cognitoClientID
        self.cognitoDomain = cognitoDomain
        self.sentryDSN = sentryDSN
        self.storeKitMonthlyProductID = storeKitMonthlyProductID
        self.storeKitAnnualProductID = storeKitAnnualProductID
        self.storeKitAnnualUpfrontProductID = storeKitAnnualUpfrontProductID
        self.environment = environment
        self.bundleIdentifier = bundleIdentifier
        self.appStoreID = appStoreID
        self.appStoreURL = appStoreURL
        self.supportURL = supportURL
        self.sentryPolicy = sentryPolicy
        self.buildConfiguration = buildConfiguration
        self.buildCommitSHA = buildCommitSHA
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.sourceIssues = sourceIssues
    }

    /// `Info.plist` keys carrying values injected by the environment xcconfig.
    public enum InfoKey {
        public static let apiBaseURL = "APIBaseURL"
        public static let cognitoRegion = "CognitoRegion"
        public static let cognitoUserPoolID = "CognitoUserPoolID"
        public static let cognitoClientID = "CognitoClientID"
        public static let cognitoDomain = "CognitoDomain"
        public static let sentryDSN = "SentryDSN"
        public static let storeKitMonthlyProductID = "SKMonthlyProductID"
        public static let storeKitAnnualProductID = "SKAnnualProductID"
        public static let storeKitAnnualUpfrontProductID = "SKAnnualUpfrontProductID"
        public static let environment = "ChapterFlowEnvironment"
        public static let bundleIdentifier = "BundleIdentifier"
        public static let appStoreID = "AppStoreID"
        public static let appStoreURL = "AppStoreURL"
        public static let supportURL = "SupportURL"
        public static let sentryPolicy = "SentryPolicy"
        public static let buildConfiguration = "BuildConfiguration"
        public static let buildCommitSHA = "BuildCommitSHA"
        public static let marketingVersion = "MarketingVersion"
        public static let buildNumber = "BuildNumber"

        static let all: [String] = [
            apiBaseURL,
            cognitoRegion,
            cognitoUserPoolID,
            cognitoClientID,
            cognitoDomain,
            sentryDSN,
            storeKitMonthlyProductID,
            storeKitAnnualProductID,
            storeKitAnnualUpfrontProductID,
            environment,
            bundleIdentifier,
            appStoreID,
            appStoreURL,
            supportURL,
            sentryPolicy,
            buildConfiguration,
            buildCommitSHA,
            marketingVersion,
            buildNumber
        ]
    }

    /// Reads configuration from the given bundle's `Info.plist`. Reading remains
    /// nonthrowing; callers explicitly decide how to handle the returned validation state.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> AppConfig {
        var values: [String: String] = [:]
        for key in InfoKey.all {
            values[key] = (bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
        }
        if values[InfoKey.bundleIdentifier, default: ""].isEmpty {
            values[InfoKey.bundleIdentifier] = bundle.bundleIdentifier ?? ""
        }
        return fromInfoValues(values)
    }

    /// Pure parsing seam used by unit tests. It remains internal so untyped
    /// dictionaries do not become part of the public configuration boundary.
    static func fromInfoValues(_ values: [String: String]) -> AppConfig {
        let environmentValue = values[InfoKey.environment, default: ""]
        let environment = AppEnvironment(configurationValue: environmentValue)
        let sentryPolicyValue = values[InfoKey.sentryPolicy, default: ""]
        let sentryPolicy = SentryPolicy(configurationValue: sentryPolicyValue)
        var sourceIssues: [ConfigurationIssue] = []

        if environment == .unknown {
            sourceIssues.append(ConfigurationIssue(
                field: .environment,
                reason: ConfigurationValueInspection.issueReason(
                    for: environmentValue,
                    required: true
                ) ?? .malformed
            ))
        }
        if sentryPolicy == .unspecified,
           !ConfigurationValueInspection.trimmed(sentryPolicyValue).isEmpty {
            sourceIssues.append(ConfigurationIssue(
                field: .sentryPolicy,
                reason: ConfigurationValueInspection.issueReason(
                    for: sentryPolicyValue,
                    required: false
                ) ?? .malformed
            ))
        }

        return AppConfig(
            apiBaseURL: values[InfoKey.apiBaseURL, default: ""],
            cognitoRegion: values[InfoKey.cognitoRegion, default: ""],
            cognitoUserPoolID: values[InfoKey.cognitoUserPoolID, default: ""],
            cognitoClientID: values[InfoKey.cognitoClientID, default: ""],
            cognitoDomain: values[InfoKey.cognitoDomain, default: ""],
            sentryDSN: values[InfoKey.sentryDSN, default: ""],
            storeKitMonthlyProductID: values[InfoKey.storeKitMonthlyProductID, default: ""],
            storeKitAnnualProductID: values[InfoKey.storeKitAnnualProductID, default: ""],
            storeKitAnnualUpfrontProductID: values[InfoKey.storeKitAnnualUpfrontProductID, default: ""],
            environment: environment,
            bundleIdentifier: values[InfoKey.bundleIdentifier, default: ""],
            appStoreID: values[InfoKey.appStoreID, default: ""],
            appStoreURL: values[InfoKey.appStoreURL, default: ""],
            supportURL: values[InfoKey.supportURL, default: ""],
            sentryPolicy: sentryPolicy,
            buildConfiguration: values[InfoKey.buildConfiguration, default: ""],
            buildCommitSHA: values[InfoKey.buildCommitSHA, default: ""],
            marketingVersion: values[InfoKey.marketingVersion, default: ""],
            buildNumber: values[InfoKey.buildNumber, default: ""],
            sourceIssues: sourceIssues
        )
    }
}
