import Foundation

/// Strongly-typed application configuration, populated from `Info.plist` keys
/// that are in turn injected from an `.xcconfig` file at build time.
///
/// The backing `Info.plist` values are wired up in the app target's build
/// settings (see `Secrets.xcconfig` / `Secrets.example.xcconfig`).
public struct AppConfig: Sendable, Equatable {
    public let apiBaseURL: String
    public let cognitoRegion: String
    public let cognitoUserPoolID: String
    public let cognitoClientID: String
    /// Custom Cognito domain, e.g. `auth.chapterflow.ca` (no https://, no trailing slash).
    public let cognitoDomain: String
    /// Sentry DSN for crash reporting. An empty string disables Sentry entirely
    /// (the default in Debug builds and when the key is absent from Info.plist).
    public let sentryDSN: String

    // MARK: - StoreKit 2 product IDs

    /// App Store product ID for the monthly auto-renewable subscription.
    /// Set via `SK_MONTHLY_PRODUCT_ID` in the xcconfig / Secrets.xcconfig.
    public let storeKitMonthlyProductID: String
    /// App Store product ID for the annual auto-renewable subscription.
    /// Set via `SK_ANNUAL_PRODUCT_ID` in the xcconfig / Secrets.xcconfig.
    public let storeKitAnnualProductID: String
    /// App Store product ID for the optional annual-upfront (non-renewing) product.
    /// Leave empty in xcconfig to omit this tier from the paywall.
    public let storeKitAnnualUpfrontProductID: String

    /// Required fields absent from the source dictionary. Directly initialized
    /// empty strings remain distinguishable as explicitly present-but-empty.
    let missingRequiredFields: Set<AppConfigurationField>

    public init(
        apiBaseURL: String,
        cognitoRegion: String,
        cognitoUserPoolID: String,
        cognitoClientID: String,
        cognitoDomain: String = "",
        sentryDSN: String = "",
        storeKitMonthlyProductID: String = "",
        storeKitAnnualProductID: String = "",
        storeKitAnnualUpfrontProductID: String = ""
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
        self.missingRequiredFields = []
    }

    /// Info.plist keys that carry the xcconfig-injected values.
    public enum InfoKey {
        public static let apiBaseURL = "APIBaseURL"
        public static let cognitoRegion = "CognitoRegion"
        public static let cognitoUserPoolID = "CognitoUserPoolID"
        public static let cognitoClientID = "CognitoClientID"
        public static let cognitoDomain = "CognitoDomain"
        /// Key injected from `SENTRY_DSN` xcconfig variable. Leave empty in
        /// Debug xcconfig to keep Sentry off during local development.
        public static let sentryDSN = "SentryDSN"
        public static let storeKitMonthlyProductID = "SKMonthlyProductID"
        public static let storeKitAnnualProductID = "SKAnnualProductID"
        public static let storeKitAnnualUpfrontProductID = "SKAnnualUpfrontProductID"
    }

    /// Reads configuration from the given bundle's Info.plist.
    ///
    /// Missing keys resolve to empty strings for source compatibility while
    /// retaining typed missing-field provenance for validation.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> AppConfig {
        fromInfoValues(bundle.infoDictionary ?? [:])
    }

    /// Dictionary-based parser used by the bundle loader and deterministic tests.
    public static func fromInfoValues(_ values: [String: Any]) -> AppConfig {
        let fields: [(AppConfigurationField, String)] = [
            (.apiBaseURL, InfoKey.apiBaseURL),
            (.cognitoRegion, InfoKey.cognitoRegion),
            (.cognitoUserPoolID, InfoKey.cognitoUserPoolID),
            (.cognitoClientID, InfoKey.cognitoClientID),
            (.cognitoDomain, InfoKey.cognitoDomain),
        ]
        let missing = Set(fields.compactMap { field, key in
            values[key] == nil ? field : nil
        })

        func value(_ key: String) -> String {
            values[key] as? String ?? ""
        }

        return AppConfig(
            apiBaseURL: value(InfoKey.apiBaseURL),
            cognitoRegion: value(InfoKey.cognitoRegion),
            cognitoUserPoolID: value(InfoKey.cognitoUserPoolID),
            cognitoClientID: value(InfoKey.cognitoClientID),
            cognitoDomain: value(InfoKey.cognitoDomain),
            sentryDSN: value(InfoKey.sentryDSN),
            storeKitMonthlyProductID: value(InfoKey.storeKitMonthlyProductID),
            storeKitAnnualProductID: value(InfoKey.storeKitAnnualProductID),
            storeKitAnnualUpfrontProductID: value(InfoKey.storeKitAnnualUpfrontProductID),
            missingRequiredFields: missing
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
        missingRequiredFields: Set<AppConfigurationField>
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
        self.missingRequiredFields = missingRequiredFields
    }
}
