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

/// Keychain-backed token store that persists the Cognito token triple.
///
/// ## Token Ownership
/// `TokenStore` is a **read-mostly mirror** of the Amplify session. In production,
/// the ONLY component that writes to this store is `AuthService`, which does so after
/// every Amplify auth event: sign-in, token refresh, and sign-out. No other code path
/// may call `save(_:)` in production.
///
/// Extensions must NOT call `save(_:)` or `delete()` — they read only the cached
/// `idToken` via `load()` for authenticated requests.
///
/// ## Keychain Security
/// Items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
/// - Available after first device unlock (required for BGTask background refresh).
/// - Never synced to iCloud Keychain or migrated to new devices.
/// - Items are scoped to the App Group access group so the main app and its
///   extensions share a single Keychain item. The `keychain-access-groups`
///   entitlement must list the same group.
///
/// Thread-safety: `save/load/delete` are individually thread-safe (Security framework
/// serialises its operations). All call sites are `@MainActor`, so no additional
/// synchronisation is needed.
public struct TokenStore: TokenStoring, Sendable {
    /// The Keychain configuration — exposed so callers can verify security
    /// attributes (accessibility, App Group) without real Keychain access in tests.
    public let configuration: KeychainConfiguration
    private let account: String

    // Uses SystemKeychain for actual Keychain operations so all queries include
    // the App Group and correct accessibility attribute without code duplication.
    private let keychain: SystemKeychain

    public init(
        configuration: KeychainConfiguration = .default,
        account: String = "auth.tokens"
    ) {
        self.configuration = configuration
        self.account = account
        self.keychain = SystemKeychain(configuration: configuration)
    }

    public func save(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.set(data, for: account)
    }

    public func load() -> StoredTokens? {
        guard let data = try? keychain.data(for: account) else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    public func delete() throws {
        try keychain.remove(account)
    }
}

// MARK: - InMemoryTokenStore

/// A non-persistent, thread-safe token store for use in tests and Previews.
///
/// The real `TokenStore` calls `SecItem*` APIs that require a keychain-access-group
/// entitlement unavailable in bare test bundles. Use this instead.
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
