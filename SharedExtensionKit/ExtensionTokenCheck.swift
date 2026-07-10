import Foundation
import Security

// MARK: - ExtensionTokenCheck
//
// Reads the Cognito id_token from the shared Keychain without importing the
// Persistence SPM package (extensions do not link the main app's packages).
// Mirrors the Keychain configuration in Persistence/TokenStore.swift — must
// stay in sync with that file.

/// Checks whether the user is currently signed in by reading the shared Keychain.
///
/// Returns `true` when a valid, non-expired `id_token` is present.
/// Extensions should call this once on launch and surface a "Sign in" prompt when
/// it returns `false` — they must never silently drop saved items.
func isSignedIn() -> Bool {
    idToken() != nil
}

/// Returns the raw Cognito `id_token` string, or `nil` when not signed in or expired.
func idToken() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.chapterflow.tokens",
        kSecAttrAccount as String: "auth.tokens",
        kSecAttrAccessGroup as String: "group.com.chapterflow",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }

    struct StoredTokens: Decodable {
        let idToken: String
        let expiresAt: Date
    }
    guard let tokens = try? JSONDecoder().decode(StoredTokens.self, from: data) else { return nil }
    return tokens.expiresAt > Date() ? tokens.idToken : nil
}
