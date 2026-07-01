import Foundation

/// A minimal, display-ready user profile derived from a Cognito id_token JWT.
///
/// The `displayName` resolution order:
///   1. `name` claim (set by Cognito from Apple's first-sign-in name disclosure)
///   2. `given_name` + `family_name` claims
///   3. `email` prefix before `@`
///   4. Fallback: `"Reader"`
public struct UserProfile: Sendable, Equatable {
    public let sub: String
    public let email: String
    public let displayName: String

    public init(sub: String, email: String, displayName: String) {
        self.sub = sub
        self.email = email
        self.displayName = displayName
    }

    /// Parses a Cognito id_token JWT (base64url-encoded) and extracts the profile.
    /// Returns `nil` if the token is malformed or the payload cannot be decoded.
    public static func from(idToken: String) -> UserProfile? {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        // Decode base64url → base64 → Data
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let payloadData = Data(base64Encoded: base64) else { return nil }

        struct Claims: Decodable {
            let sub: String?
            let email: String?
            let name: String?
            let given_name: String?
            let family_name: String?
        }

        guard let claims = try? JSONDecoder().decode(Claims.self, from: payloadData) else {
            return nil
        }

        let resolvedName: String
        if let n = claims.name, !n.trimmingCharacters(in: .whitespaces).isEmpty {
            resolvedName = n
        } else if let first = claims.given_name, !first.isEmpty {
            let last = claims.family_name.map { " \($0)" } ?? ""
            resolvedName = (first + last).trimmingCharacters(in: .whitespaces)
        } else if let email = claims.email,
                  let prefix = email.split(separator: "@").first,
                  !prefix.isEmpty {
            resolvedName = String(prefix)
        } else {
            resolvedName = "Reader"
        }

        return UserProfile(
            sub: claims.sub ?? "",
            email: claims.email ?? "",
            displayName: resolvedName.isEmpty ? "Reader" : resolvedName
        )
    }
}
