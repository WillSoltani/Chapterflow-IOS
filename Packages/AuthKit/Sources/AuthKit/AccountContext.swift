import CoreKit
import CryptoKit
import Foundation

/// Immutable account authority passed to dependencies that live for one signed-in session.
///
/// `AccountContext` does not replace ``SessionIdentity`` or perform authentication. It maps
/// already-proven session identity and validated configuration into stable, privacy-safe
/// namespaces while assigning each constructed session scope a unique instance identity.
public struct AccountContext: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The stable Cognito subject proven by the active session.
    public let accountID: String

    /// Identifies the concrete account-lifetime scope, not the durable account.
    public let instanceID: UUID

    /// Stable opaque namespace for the validated API and Cognito environment.
    public let environmentNamespace: String

    /// Stable opaque namespace for private persistence owned by this account and environment.
    public let storageNamespace: String

    /// Authentication source already proven by ``SessionIdentity``.
    public let source: SessionIdentity.Source

    /// Creates account-lifetime authority only from proven identity and validated configuration.
    public init(identity: SessionIdentity, config: ValidatedAppConfig) {
        accountID = identity.subject
        instanceID = UUID()
        source = identity.source

        let environmentDigest = Self.digest([
            ("api_base_url", config.value.apiBaseURL),
            ("cognito_region", config.value.cognitoRegion),
            ("cognito_user_pool_id", config.value.cognitoUserPoolID),
            ("cognito_client_id", config.value.cognitoClientID),
            ("cognito_domain", config.value.cognitoDomain),
        ])
        environmentNamespace = "environment-v1-\(environmentDigest)"
        let storageDigest = Self.digest([
            ("environment_namespace", environmentNamespace),
            ("account_subject", identity.subject),
        ])
        storageNamespace = "account-v1-\(storageDigest)"
    }

    public var description: String {
        "AccountContext(redacted, source: \(source.rawValue))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "source": source.rawValue,
            "identity": "redacted",
            "environment": "redacted",
            "instance": "redacted",
        ])
    }

    private static func digest(_ fields: [(String, String)]) -> String {
        var input = Data()
        for (name, value) in fields {
            appendLengthPrefixed(name, to: &input)
            appendLengthPrefixed(value, to: &input)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLengthPrefixed(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
