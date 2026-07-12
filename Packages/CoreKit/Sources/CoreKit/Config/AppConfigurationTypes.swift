/// The backend and Apple-services environment selected by the build configuration.
public enum AppEnvironment: String, Codable, Sendable, Equatable, CaseIterable {
    case development
    case staging
    case production
    case unknown

    public init(configurationValue: String) {
        switch ConfigurationValueInspection.trimmed(configurationValue).lowercased() {
        case "development", "debug":
            self = .development
        case "staging":
            self = .staging
        case "production", "release":
            self = .production
        default:
            self = .unknown
        }
    }
}

/// Explicit build policy controlling whether Sentry may be initialized.
public enum SentryPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case enabled
    case disabled
    case unspecified

    public init(configurationValue: String) {
        switch ConfigurationValueInspection.trimmed(configurationValue).lowercased() {
        case "enabled":
            self = .enabled
        case "disabled":
            self = .disabled
        default:
            self = .unspecified
        }
    }
}

/// A privacy-safe, stable description of one configuration failure.
/// It intentionally contains no configuration value, URL, identifier, or secret.
public struct ConfigurationIssue: Equatable, Sendable {
    public enum Field: String, Codable, Sendable, Equatable, CaseIterable {
        case environment
        case apiBaseURL = "api_base_url"
        case cognitoRegion = "cognito_region"
        case cognitoUserPoolID = "cognito_user_pool_id"
        case cognitoClientID = "cognito_client_id"
        case cognitoDomain = "cognito_domain"
        case bundleIdentifier = "bundle_identifier"
        case appStoreID = "app_store_id"
        case appStoreURL = "app_store_url"
        case supportURL = "support_url"
        case storeKitMonthlyProductID = "storekit_monthly_product_id"
        case storeKitAnnualProductID = "storekit_annual_product_id"
        case storeKitAnnualUpfrontProductID = "storekit_annual_upfront_product_id"
        case sentryPolicy = "sentry_policy"
        case sentryDSN = "sentry_dsn"
        case buildConfiguration = "build_configuration"
        case buildCommitSHA = "build_commit_sha"
        case marketingVersion = "marketing_version"
        case buildNumber = "build_number"
    }

    public enum Reason: String, Codable, Sendable, Equatable, CaseIterable {
        case missing
        case unexpanded
        case placeholder
        case malformed
        case insecure
        case disallowedHost = "disallowed_host"
        case mismatch
        case duplicate
        case inconsistent
        case unsupported
    }

    public let field: Field
    public let reason: Reason

    /// Stable diagnostic code safe for logs, CI output, and support screens.
    public var code: String {
        "configuration.\(field.rawValue).\(reason.rawValue)"
    }

    public init(field: Field, reason: Reason) {
        self.field = field
        self.reason = reason
    }
}

/// Result of evaluating an `AppConfig` before constructing production services.
public enum AppConfigurationState: Equatable, Sendable {
    case unvalidated
    case valid(config: AppConfig, environment: AppEnvironment)
    case invalid(config: AppConfig, issues: [ConfigurationIssue])
}

/// Redacted build diagnostics. No token, DSN, URL path, Cognito identifier, or
/// StoreKit product identifier is retained.
public struct BuildDiagnosticsRecord: Equatable, Sendable {
    public let environment: AppEnvironment
    public let apiHost: String
    public let bundleIdentifier: String
    public let marketingVersion: String
    public let buildNumber: String
    public let buildConfiguration: String
    public let buildCommitSHA: String
    public let storeKitProductCount: Int
    public let sentryEnabled: Bool

    public init(
        environment: AppEnvironment,
        apiHost: String,
        bundleIdentifier: String,
        marketingVersion: String,
        buildNumber: String,
        buildConfiguration: String,
        buildCommitSHA: String,
        storeKitProductCount: Int,
        sentryEnabled: Bool
    ) {
        self.environment = environment
        self.apiHost = apiHost
        self.bundleIdentifier = bundleIdentifier
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.buildConfiguration = buildConfiguration
        self.buildCommitSHA = buildCommitSHA
        self.storeKitProductCount = storeKitProductCount
        self.sentryEnabled = sentryEnabled
    }
}
