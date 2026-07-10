import Foundation

// MARK: - Alternate-key tolerant decoding
//
// The deployed web API hand-projects each route's JSON and is inconsistent
// about key names route-to-route (`id` vs `bookId`, `publishedVersion` vs
// `latestVersion`, `minutes` vs `readingTimeMinutes`, …). Locally persisted
// caches and fixtures, meanwhile, use the canonical names the models encode.
// These helpers let a model accept every known spelling while always
// ENCODING the canonical one, so cached data and wire data both decode.
// See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.

extension KeyedDecodingContainer {
    /// Returns the first present-and-decodable value among `keys`, in order.
    /// A key that is present but fails to decode as `T` is skipped, so one
    /// malformed alternate never masks a valid canonical value (or vice versa).
    public func decodeFirst<T: Decodable>(_ type: T.Type, keys: [Key]) -> T? {
        for key in keys {
            if let value = ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) {
                return value
            }
        }
        return nil
    }

    /// Like `decodeFirst`, but throws `.keyNotFound` for the FIRST (canonical)
    /// key when no alternate yields a value. Use for identity fields that a
    /// model cannot exist without (ids). The error names the canonical key so
    /// drift logs stay readable.
    public func decodeRequiredFirst<T: Decodable>(_ type: T.Type, keys: [Key]) throws -> T {
        if let value = decodeFirst(type, keys: keys) { return value }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription:
                    "None of the accepted keys \(keys.map(\.stringValue)) were present/decodable."
            )
        )
    }
}

/// Decodes a JSON array lossily from any decoder position (top-level bare
/// arrays included): elements that fail to decode are dropped, never throwing
/// for the collection itself. Companion to `KeyedDecodingContainer.decodeLossy`.
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    private struct AlwaysDecodes: Decodable {
        let value: Element?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(Element.self)
        }
    }

    public init(from decoder: any Decoder) throws {
        var unkeyed = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !unkeyed.isAtEnd {
            let wrapper = try unkeyed.decode(AlwaysDecodes.self)
            if let value = wrapper.value { result.append(value) }
        }
        elements = result
    }
}
