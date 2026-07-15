import Foundation
import Security

// MARK: - StoredTokens

/// Tokens persisted to the Keychain after a successful Cognito auth operation.
public struct StoredTokens: Sendable, Codable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
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

    /// Token values are secrets and must never enter logs or debugger reflection.
    public var description: String { "StoredTokens(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["contents": "redacted"])
    }
}

// MARK: - TokenStoring

/// Abstraction over token persistence, enabling in-memory fakes in tests.
public protocol TokenStoring: Sendable {
    func save(_ tokens: StoredTokens) throws
    func load() throws -> StoredTokens?
    func delete() throws
}

// MARK: - TokenStore

/// Keychain-backed token store that persists the Cognito token triple.
///
/// ## Token Ownership
/// `TokenStore` is a **read-mostly mirror** of the Amplify session. In production,
/// the AuthKit `SessionManager` lifecycle authority is the only component that writes
/// to this store, after it has verified sign-in, restoration, or refresh through the
/// active Amplify/Cognito session. No other production path may call `save(_:)`.
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

    public func load() throws -> StoredTokens? {
        guard let data = try keychain.data(for: account) else { return nil }
        do {
            return try JSONDecoder().decode(StoredTokens.self, from: data)
        } catch {
            throw PersistenceError.invalidTokenData
        }
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

    public func load() throws -> StoredTokens? {
        lock.withLock { _tokens }
    }

    public func delete() throws {
        lock.withLock { _tokens = nil }
    }
}
