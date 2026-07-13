/// A required development-service value supplied through build configuration.
public enum AppConfigurationField: String, CaseIterable, Codable, Hashable, Sendable {
    case apiBaseURL = "api_base_url"
    case cognitoRegion = "cognito_region"
    case cognitoUserPoolID = "cognito_user_pool_id"
    case cognitoClientID = "cognito_client_id"
    case cognitoDomain = "cognito_domain"

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

/// A privacy-safe classification of a configuration problem.
///
/// Categories intentionally carry no associated value so diagnostics cannot
/// accidentally retain an endpoint or Cognito identifier.
public enum AppConfigurationIssueCategory: String, CaseIterable, Codable, Sendable {
    case missing
    case empty
    case unexpanded
    case templateValue = "template_value"
    case placeholder
    case malformed
    case insecureTransport = "insecure_transport"
    case regionMismatch = "region_mismatch"

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

/// One deterministic, nonsecret configuration issue.
public struct AppConfigurationIssue: Equatable, Hashable, Codable, Sendable {
    public let field: AppConfigurationField
    public let category: AppConfigurationIssueCategory

    /// Stable code safe for local diagnostics and support reports.
    public var code: String {
        "configuration.\(field.rawValue).\(category.rawValue)"
    }

    public init(field: AppConfigurationField, category: AppConfigurationIssueCategory) {
        self.field = field
        self.category = category
    }
}

/// Capability proving that the five required API/Cognito values were checked.
/// Only ``AppConfig/validate()`` can create this wrapper.
public struct ValidatedAppConfig: Equatable, Sendable {
    public let value: AppConfig
}

/// The complete result of synchronous configuration validation.
///
/// The invalid case retains issues only. Raw configuration values therefore do
/// not cross into the failure UI or diagnostics path.
public enum AppConfigurationValidation: Equatable, Sendable {
    case valid(ValidatedAppConfig)
    case invalid([AppConfigurationIssue])
}
