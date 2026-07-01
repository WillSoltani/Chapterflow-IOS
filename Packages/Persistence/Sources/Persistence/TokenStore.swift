import Foundation
import Security

// MARK: - StoredTokens

/// Tokens persisted to the Keychain after a successful Cognito auth operation.
public struct StoredTokens: Sendable, Codable, Equatable {
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    /// Absolute expiry derived from the JWT `exp` claim.
    public let expiresAt: Date

    public init(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }

    /// Returns `true` when within 5 minutes of expiry — triggers a proactive refresh.
    public func isNearlyExpired(at date: Date = Date()) -> Bool {
        date.addingTimeInterval(300) >= expiresAt
    }
}

// MARK: - TokenStoring

/// Abstraction over token persistence, enabling in-memory fakes in tests.
public protocol TokenStoring: Sendable {
    func save(_ tokens: StoredTokens) throws
    func load() -> StoredTokens?
    func delete() throws
}

// MARK: - TokenStore

/// Keychain-backed token store. Thread-safe: the Security framework serialises
/// its own operations, and this type is a value with no mutable state.
public struct TokenStore: TokenStoring, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.chapterflow.ios",
        account: String = "auth.tokens"
    ) {
        self.service = service
        self.account = account
    }

    public func save(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        // Delete any existing item first so SecItemAdd always succeeds.
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError.writeFailed(status)
        }
    }

    public func load() -> StoredTokens? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    public func delete() throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.deleteFailed(status)
        }
    }
}

// MARK: - InMemoryTokenStore

/// A non-persistent, thread-safe token store for use in tests and Previews.
public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _tokens: StoredTokens?

    public init(tokens: StoredTokens? = nil) {
        self._tokens = tokens
    }

    public func save(_ tokens: StoredTokens) throws {
        lock.withLock { _tokens = tokens }
    }

    public func load() -> StoredTokens? {
        lock.withLock { _tokens }
    }

    public func delete() throws {
        lock.withLock { _tokens = nil }
    }
}

// MARK: - Errors

public enum TokenStoreError: Error, Sendable {
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
}
