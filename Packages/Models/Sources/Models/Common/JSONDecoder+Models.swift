import Foundation

public extension JSONDecoder {
    /// The shared decoder for all ChapterFlow model decoding.
    ///
    /// Configured with a tolerant ISO-8601 date strategy that accepts both
    /// fractional-second and whole-second timestamps. No key-conversion strategy
    /// is needed since the API uses `lowerCamel` keys that match Swift property names.
    static let chapterFlow: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected ISO-8601 date string, got \"\(string)\"."
                )
            )
        }
        return d
    }()
}
