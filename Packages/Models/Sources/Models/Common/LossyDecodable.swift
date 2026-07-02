import Foundation
import OSLog

private let _decodeLog = Logger(subsystem: "com.chapterflow.models", category: "decoding")

// MARK: - Fail-safe wrapper

/// A private Decodable wrapper whose init always succeeds.
/// Used inside `decodeLossy` to advance the unkeyed-container cursor even when
/// the target type fails to decode.
private struct FailSafeWrapper<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

// MARK: - KeyedDecodingContainer extension

extension KeyedDecodingContainer {
    /// Decodes a JSON array lossily under `key`.
    ///
    /// Elements that fail to decode are dropped and logged; the collection decode
    /// always succeeds even if every element is malformed. This matches the
    /// ChapterFlow server-evolution contract: additive server changes must never
    /// crash a released app.
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        var unkeyed = try nestedUnkeyedContainer(forKey: key)
        var result: [T] = []
        while !unkeyed.isAtEnd {
            // FailSafeWrapper always succeeds, advancing the cursor regardless
            // of whether the inner T decode succeeds.
            let wrapper = try unkeyed.decode(FailSafeWrapper<T>.self)
            if let value = wrapper.value {
                result.append(value)
            } else {
                _decodeLog.warning(
                    "[\(String(describing: T.self))] Dropped malformed element during lossy array decode"
                )
            }
        }
        return result
    }
}
