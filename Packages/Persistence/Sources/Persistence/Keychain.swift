import Foundation
import Security

/// Keychain accessibility policy for stored items.
public enum KeychainAccessibility: Sendable {
    /// Readable after the first unlock following boot, never migrated to other devices.
    case afterFirstUnlockThisDeviceOnly

    var secValue: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

/// Configuration for a Keychain-backed store.
public struct KeychainConfiguration: Sendable {
    /// The `kSecAttrService` used to namespace items.
    public var service: String
    /// The Keychain access group for sharing tokens with app extensions and widgets.
    /// Set to the App Group identifier so extensions can read the token for authenticated
    /// requests. Must also be listed in the `keychain-access-groups` entitlement.
    public var accessGroup: String?
    /// The accessibility class applied to written items.
    public var accessibility: KeychainAccessibility

    public init(
        service: String = "com.chapterflow.tokens",
        accessGroup: String? = AppGroup.identifier,
        accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    /// The default token store configuration.
    ///
    /// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so tokens survive
    /// device reboots (required for background BGTask refresh) but never migrate to
    /// new devices via iCloud Keychain backup. The App Group access group allows
    /// the main app and its extensions to share the same token item.
    public static let `default` = KeychainConfiguration(
        service: "com.chapterflow.tokens",
        accessGroup: AppGroup.identifier,
        accessibility: .afterFirstUnlockThisDeviceOnly
    )
}

/// A backing store for the token triple. `SystemKeychain` is the production
/// implementation; ``InMemoryKeychain`` is an in-memory fake for fast, deterministic
/// tests (a bare test bundle has no keychain-access-group entitlement, so the real
/// `SecItem` API returns `errSecMissingEntitlement` outside a host app).
protocol KeychainStoring: Sendable {
    func set(_ data: Data, for account: String) throws
    func data(for account: String) throws -> Data?
    func remove(_ account: String) throws
}

extension KeychainStoring {
    /// Reads a UTF-8 string for `account`, or `nil` if absent.
    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }
}

/// A thin, synchronous wrapper over the `kSecClassGenericPassword` Keychain API.
///
/// Callers should serialize access (e.g. from an actor) — the individual `Sec*` calls
/// are thread-safe but read-modify-write sequences are not.
struct SystemKeychain: KeychainStoring, Sendable {
    let configuration: KeychainConfiguration

    /// Builds the base query for a given account, without value/return attributes.
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: account
        ]
        if let group = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        #if os(macOS)
        // Use the iOS-style data-protection keychain so accessibility classes apply.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// Stores `data` for `account`, replacing any existing item.
    func set(_ data: Data, for account: String) throws {
        // Delete any existing item first so we can add with fresh attributes.
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = configuration.accessibility.secValue

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PersistenceError.keychain(status)
        }
    }

    /// Reads the raw data for `account`, or `nil` if absent.
    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw PersistenceError.keychain(status)
        }
    }

    /// Removes the item for `account` (no-op if it does not exist).
    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PersistenceError.keychain(status)
        }
    }
}

/// An in-memory ``KeychainStoring`` fake for tests and previews.
///
/// Mutations are protected by an `NSLock` so this can be used from any thread
/// without external serialisation. Use this whenever the real `SecItem` API is
/// unavailable (e.g. test bundles without the `keychain-access-groups` entitlement).
final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for account: String) throws {
        lock.withLock { storage[account] = data }
    }

    func data(for account: String) throws -> Data? {
        lock.withLock { storage[account] }
    }

    func remove(_ account: String) throws {
        lock.withLock { storage[account] = nil }
    }
}
