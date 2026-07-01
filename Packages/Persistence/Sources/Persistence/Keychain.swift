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
    /// The shared keychain access group (nil = the app's default group). Set this to a
    /// keychain-sharing group listed in entitlements to share tokens with extensions.
    public var accessGroup: String?
    /// The accessibility class applied to written items.
    public var accessibility: KeychainAccessibility

    public init(
        service: String = "com.chapterflow.tokens",
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    /// The default token store configuration.
    public static let `default` = KeychainConfiguration()
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
        return String(decoding: data, as: UTF8.self)
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
            kSecAttrAccount as String: account,
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
/// Access is serialized by the owning ``TokenStore`` actor, so the mutable dictionary
/// is safe despite the `@unchecked Sendable` conformance.
final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for account: String) throws {
        storage[account] = data
    }

    func data(for account: String) throws -> Data? {
        storage[account]
    }

    func remove(_ account: String) throws {
        storage[account] = nil
    }
}
