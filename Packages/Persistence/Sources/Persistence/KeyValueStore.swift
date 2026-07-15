import Foundation

/// A small typed wrapper over `UserDefaults` for storing `Codable` values as JSON.
///
/// Use it for lightweight, non-sensitive state that doesn't warrant SwiftData. For
/// tokens use ``TokenStore``; for large blobs use ``FileStore``.
public struct KeyValueStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keyPrefix: String?

    /// Creates a store over the given defaults (App Group suite by default).
    ///
    /// When `keyPrefix` is present, it is prepended verbatim to every key used by
    /// this store. Include any desired separator in the prefix itself. Omitting
    /// the prefix preserves the historical key layout.
    public init(defaults: UserDefaults? = nil, keyPrefix: String? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        self.keyPrefix = keyPrefix
    }

    /// Decodes and returns the value for `key`, or `nil` if absent/undecodable.
    public func value<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Encodes and stores `value` for `key`.
    public func set<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: storageKey(for: key))
    }

    /// Removes any value stored for `key`.
    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    /// Whether a value exists for `key`.
    public func contains(_ key: String) -> Bool {
        defaults.object(forKey: storageKey(for: key)) != nil
    }

    private func storageKey(for key: String) -> String {
        guard let keyPrefix else { return key }
        return keyPrefix + key
    }
}
