import Foundation

/// Stable identity proven by the active Cognito user-pool session.
///
/// Display metadata is optional and never participates in authentication.
/// The subject is validated once at construction so `.signedIn` cannot carry an
/// empty, anonymous, local, or generated fallback identity.
public struct SessionIdentity: Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public enum Source: String, Sendable, Equatable {
        case cognitoUserPool
        case hermeticUITest
    }

    public let subject: String
    public let displayUsername: String?
    public let email: String?
    public let source: Source

    public init?(
        subject: String,
        username: String?,
        email: String?,
        source: Source
    ) {
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = ["anon", "local"]
        guard !normalizedSubject.isEmpty,
              normalizedSubject == subject,
              !disallowed.contains(normalizedSubject.lowercased()) else {
            return nil
        }

        self.subject = normalizedSubject
        self.displayUsername = Self.normalizedOptional(username)
        self.email = Self.normalizedOptional(email)
        self.source = source
    }

    /// Compatibility name used by existing account-scoped consumers.
    public var userId: String { subject }

    /// Compatibility display value; never use this as an authority key.
    public var username: String { displayUsername ?? "" }

    public var userSummary: UserSummary {
        UserSummary(userId: subject, username: username, email: email)
    }

    public var description: String { "SessionIdentity(redacted, source: \(source.rawValue))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["source": source.rawValue, "identity": "redacted"])
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

public enum AuthProvider: String, Sendable, Equatable {
    case apple
}

/// Stable, privacy-safe failure used while an external provider is not configured.
public enum AuthProviderError: Error, Sendable, Equatable,
    LocalizedError, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case unavailable(AuthProvider)

    public var errorDescription: String? {
        "This sign-in provider is currently unavailable."
    }

    public var description: String { "AuthProviderError.unavailable" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["status": "unavailable"])
    }
}
