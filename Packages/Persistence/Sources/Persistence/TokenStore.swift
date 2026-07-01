import Foundation

/// An actor that securely stores, loads, and clears the Cognito auth tokens in the
/// Keychain, and broadcasts changes via an `AsyncStream`.
///
/// Tokens are stored as three `kSecClassGenericPassword` items (id/access/refresh) with
/// `afterFirstUnlockThisDeviceOnly` accessibility so background tasks (sync, widgets)
/// can read them after first unlock, while never leaving the device.
public actor TokenStore {
    /// The Cognito token triple.
    public struct Tokens: Sendable, Equatable {
        /// The Cognito `id_token` (JWT) sent as `Authorization: Bearer`.
        public var idToken: String
        /// The Cognito `access_token`.
        public var accessToken: String
        /// The Cognito `refresh_token`.
        public var refreshToken: String

        public init(idToken: String, accessToken: String, refreshToken: String) {
            self.idToken = idToken
            self.accessToken = accessToken
            self.refreshToken = refreshToken
        }
    }

    private enum Account {
        static let id = "cognito.idToken"
        static let access = "cognito.accessToken"
        static let refresh = "cognito.refreshToken"
    }

    private let keychain: any KeychainStoring
    private var observers: [UUID: AsyncStream<Tokens?>.Continuation] = [:]

    /// Creates a token store backed by the system Keychain.
    public init(configuration: KeychainConfiguration = .default) {
        self.keychain = SystemKeychain(configuration: configuration)
    }

    /// Creates a token store over a custom backing store (used by tests/previews).
    init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    /// Persists the full token triple and notifies observers.
    public func save(_ tokens: Tokens) throws {
        try keychain.set(Data(tokens.idToken.utf8), for: Account.id)
        try keychain.set(Data(tokens.accessToken.utf8), for: Account.access)
        try keychain.set(Data(tokens.refreshToken.utf8), for: Account.refresh)
        broadcast(tokens)
    }

    /// Loads the token triple, or `nil` if any token is missing.
    public func load() throws -> Tokens? {
        guard
            let id = try keychain.string(for: Account.id),
            let access = try keychain.string(for: Account.access),
            let refresh = try keychain.string(for: Account.refresh)
        else {
            return nil
        }
        return Tokens(idToken: id, accessToken: access, refreshToken: refresh)
    }

    /// Removes all tokens and notifies observers with `nil`.
    public func clear() throws {
        try keychain.remove(Account.id)
        try keychain.remove(Account.access)
        try keychain.remove(Account.refresh)
        broadcast(nil)
    }

    /// A stream that yields the new token state whenever it is saved or cleared.
    ///
    /// Multiple concurrent consumers are supported; each gets its own stream.
    public func changes() -> AsyncStream<Tokens?> {
        let (stream, continuation) = AsyncStream<Tokens?>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func broadcast(_ tokens: Tokens?) {
        for continuation in observers.values {
            continuation.yield(tokens)
        }
    }
}
