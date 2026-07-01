import Foundation

/// A small typed wrapper over `UserDefaults` for storing `Codable` values as JSON.
///
/// Use it for lightweight, non-sensitive state that doesn't warrant SwiftData. For
/// tokens use ``TokenStore``; for large blobs use ``FileStore``.
public struct KeyValueStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store over the given defaults (App Group suite by default).
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Decodes and returns the value for `key`, or `nil` if absent/undecodable.
    public func value<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Encodes and stores `value` for `key`.
    public func set<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    /// Removes any value stored for `key`.
    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    /// Whether a value exists for `key`.
    public func contains(_ key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }
}
