import Foundation
import Security

/// Protocol over the token store so `SessionManager` is testable without
/// real Keychain access.
public protocol TokenStoring: Sendable {
    func idToken() -> String?
    func refreshToken() -> String?
    func store(idToken: String, refreshToken: String)
    func clearAll()
}

/// Persists Cognito tokens in the device Keychain.
///
/// Tokens are stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// so they survive a device reboot but cannot be migrated to another device.
public struct KeychainTokenStore: TokenStoring {
    public static let shared = KeychainTokenStore()

    private let service: String

    public init(service: String = "com.chapterflow.ios.tokens") {
        self.service = service
    }

    // MARK: - TokenStoring

    public func idToken() -> String? { read(key: "id_token") }
    public func refreshToken() -> String? { read(key: "refresh_token") }

    public func store(idToken: String, refreshToken: String) {
        write(key: "id_token", value: idToken)
        write(key: "refresh_token", value: refreshToken)
    }

    public func clearAll() {
        delete(key: "id_token")
        delete(key: "refresh_token")
    }

    // MARK: - Keychain CRUD

    private func baseQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
    }

    private func read(key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        if read(key: key) != nil {
            SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
        } else {
            var query = baseQuery(for: key)
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func delete(key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }
}

/// An in-memory token store for previews and unit tests.
public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var _tokens: [String: String] = [:]

    public init(idToken: String? = nil, refreshToken: String? = nil) {
        if let id = idToken { _tokens["id_token"] = id }
        if let refresh = refreshToken { _tokens["refresh_token"] = refresh }
    }

    public func idToken() -> String? { _tokens["id_token"] }
    public func refreshToken() -> String? { _tokens["refresh_token"] }

    public func store(idToken: String, refreshToken: String) {
        _tokens["id_token"] = idToken
        _tokens["refresh_token"] = refreshToken
    }

    public func clearAll() { _tokens.removeAll() }
}
