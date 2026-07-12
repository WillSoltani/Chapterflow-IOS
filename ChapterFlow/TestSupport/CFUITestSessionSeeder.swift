#if DEBUG
import Foundation
import Security

/// Seeds the Keychain with a fake StoredTokens record so the app presents as
/// signed-in when ``CF_UITEST_BYPASS_AUTH=1`` is set in the XCUITest launch
/// environment.
///
/// Called from ``CFAppLaunchSupport.applyUITestOverrides()`` before AppFeature
/// initializes any auth-touching code. Never compiled into release builds.
///
/// The Keychain item is written to the exact location that ``TokenStore.load()``
/// reads from:
///   service = "com.chapterflow.tokens"
///   account = "auth.tokens"
///   accessGroup = "group.com.chapterflow"
///   format = JSONEncoder().encode(StoredTokens) — Date encoded as
///            timeIntervalSinceReferenceDate (Swift Foundation default)
enum CFUITestSessionSeeder {

    // MARK: - Public API

    static func seedIfNeeded() {
        // Encode a StoredTokens-compatible JSON blob.
        // StoredTokens uses JSONEncoder/Decoder with the default Date strategy
        // (timeIntervalSinceReferenceDate). We produce the same encoding manually
        // so we don't need to import Persistence here.
        //
        // expiresAt = 9_999_999_999 seconds since 1970
        //           = 9_999_999_999 - 978_307_200 = 9_021_692_799 since reference date
        let expiresAtRef: Double = 9_021_692_799.0
        let json = """
        {"idToken":"\(fakeIdToken)",\
        "accessToken":"fake-access-token-uitest",\
        "refreshToken":"fake-refresh-token-uitest",\
        "expiresAt":\(expiresAtRef)}
        """
        guard let data = json.data(using: .utf8) else { return }

        // Write to the same Keychain slot that TokenStore reads from.
        // In the iOS Simulator, access-group restrictions are not enforced for
        // unsigned builds, so writing with the App Group identifier works.
        var attrs: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      "com.chapterflow.tokens",
            kSecAttrAccount:      "auth.tokens",
            kSecAttrAccessGroup:  "group.com.chapterflow",
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData:        data,
        ]
        // Remove any stale item, then add the fresh seed.
        var deleteQuery = attrs
        deleteQuery.removeValue(forKey: kSecValueData)
        deleteQuery.removeValue(forKey: kSecAttrAccessible)
        SecItemDelete(deleteQuery as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
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
            {"sub":"00000000-0000-4000-8000-000000000123","email":"test@chapterflow.com",\
            "name":"Test User","exp":9999999999,"iat":1750000000,\
            "cognito:username":"00000000-0000-4000-8000-000000000123"}
            """
        )
        return "\(header).\(payload).fakesig"
    }()

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
