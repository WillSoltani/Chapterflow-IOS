#if DEBUG
import Foundation
import Security

/// Seeds the Keychain with a fake test JWT so the app presents as signed-in
/// when ``CF_UITEST_BYPASS_AUTH=1`` is set in the XCUITest launch environment.
///
/// Called from ``CFAppLaunchSupport.applyUITestOverrides()`` before AppFeature
/// initializes any auth-touching code. Never compiled into release builds.
enum CFUITestSessionSeeder {

    // MARK: - Public API

    static func seedIfNeeded() {
        write(service: "com.chapterflow.tokens.idToken",     value: fakeIdToken)
        write(service: "com.chapterflow.tokens.accessToken", value: "fake-access-token-uitest")
        write(service: "com.chapterflow.tokens.refreshToken",value: "fake-refresh-token-uitest")
        // expiresAt as a Unix timestamp string far in the future (year 2286)
        write(service: "com.chapterflow.tokens.expiresAt",   value: "9999999999.0")
    }

    // MARK: - Fake JWT

    /// A structurally valid but cryptographically unsigned JWT carrying the
    /// test user's claims. The stub server never verifies signatures, so this
    /// lets the app decode the user's display name from the token without
    /// making real Cognito round-trips.
    private static let fakeIdToken: String = {
        let header  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" // {"alg":"HS256","typ":"JWT"}
        let payload = base64url(
            """
            {"sub":"uitest-user-123","email":"test@chapterflow.com",\
            "name":"Test User","exp":9999999999,"iat":1750000000,\
            "cognito:username":"uitest-user-123"}
            """
        )
        return "\(header).\(payload).fakesig"
    }()

    // MARK: - Keychain writes

    private static func write(service: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      "chapterflow",
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Delete any stale item, then add fresh.
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Base64url (no padding)

    private static func base64url(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
