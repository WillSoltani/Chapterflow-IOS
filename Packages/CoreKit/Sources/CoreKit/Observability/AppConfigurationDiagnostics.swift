/// Coarse build identity safe to expose in local configuration diagnostics.
public enum AppBuildConfiguration: String, Equatable, Sendable {
    case debug
    case nonDebug = "non_debug"
}

/// A redacted snapshot of bootstrap validation and service readiness.
///
/// The record intentionally has no raw configuration, URL, Cognito identifier,
/// token, credential, request body, or personal-data field.
public struct AppConfigurationDiagnosticRecord: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case valid
        case invalid
    }

    public static let supportCode = "CF-DEV-CFG-001"

    public let status: Status
    public let buildConfiguration: AppBuildConfiguration
    public let issues: [AppConfigurationIssue]
    public let liveServicesConstructed: Bool
    public let supportCode: String

    public init(
        status: Status,
        buildConfiguration: AppBuildConfiguration,
        issues: [AppConfigurationIssue],
        liveServicesConstructed: Bool,
        supportCode: String = Self.supportCode
    ) {
        self.status = status
        self.buildConfiguration = buildConfiguration
        self.issues = issues
        self.liveServicesConstructed = liveServicesConstructed
        self.supportCode = supportCode
    }
}

/// Optional sink for privacy-safe configuration diagnostics.
/// Recording failures are deliberately ignored by the bootstrap boundary.
public protocol AppConfigurationDiagnosticsRecording: Sendable {
    func record(_ record: AppConfigurationDiagnosticRecord) throws
}

public struct NoopAppConfigurationDiagnosticsRecorder: AppConfigurationDiagnosticsRecording {
    public init() {}

    public func record(_ record: AppConfigurationDiagnosticRecord) throws {}
}
