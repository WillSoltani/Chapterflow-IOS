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

    public init(
        apiBaseURL: String,
        cognitoRegion: String,
        cognitoUserPoolID: String,
        cognitoClientID: String,
        cognitoDomain: String = ""
    ) {
        self.apiBaseURL = apiBaseURL
        self.cognitoRegion = cognitoRegion
        self.cognitoUserPoolID = cognitoUserPoolID
        self.cognitoClientID = cognitoClientID
        self.cognitoDomain = cognitoDomain
    }

    /// Info.plist keys that carry the xcconfig-injected values.
    public enum InfoKey {
        public static let apiBaseURL = "APIBaseURL"
        public static let cognitoRegion = "CognitoRegion"
        public static let cognitoUserPoolID = "CognitoUserPoolID"
        public static let cognitoClientID = "CognitoClientID"
        public static let cognitoDomain = "CognitoDomain"
    }

    /// Reads configuration from the given bundle's Info.plist.
    ///
    /// Missing keys resolve to an empty string rather than trapping, so the app
    /// still launches during early development when secrets are not yet set.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
        }
        return AppConfig(
            apiBaseURL: value(InfoKey.apiBaseURL),
            cognitoRegion: value(InfoKey.cognitoRegion),
            cognitoUserPoolID: value(InfoKey.cognitoUserPoolID),
            cognitoClientID: value(InfoKey.cognitoClientID),
            cognitoDomain: value(InfoKey.cognitoDomain)
        )
    }
}
