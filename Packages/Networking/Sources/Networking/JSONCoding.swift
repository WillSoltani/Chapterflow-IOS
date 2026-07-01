import Foundation

/// The shared JSON encoder/decoder configuration used for every request and
/// response in the app.
///
/// The ChapterFlow API speaks ISO-8601 date strings (sometimes with fractional
/// seconds, sometimes without) and `lowerCamel` keys — which match Swift's
/// property names, so no key-conversion strategy is needed. Dates are parsed
/// with a tolerant strategy that accepts both fractional and whole-second
/// timestamps, and always *emitted* with fractional seconds.
public enum JSONCoding {
    /// The canonical decoder. Use this everywhere response bodies are decoded so
    /// date handling stays consistent.
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // `ISO8601FormatStyle` is a Sendable value type, so constructing it
            // inside this `@Sendable` closure avoids capturing shared mutable state.
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an ISO-8601 date string but found \"\(string)\"."
                )
            )
        }
        return decoder
    }()

    /// The canonical encoder, used for request bodies.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()
}
