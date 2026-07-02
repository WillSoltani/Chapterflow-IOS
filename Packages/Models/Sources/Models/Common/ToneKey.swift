/// The three reading-tone options a user can select throughout the app.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Every switch over this enum must handle `.unknown` explicitly —
/// the recommended fallback is to treat it like `.gentle`.
public enum ToneKey: Sendable, Equatable, Hashable {
    case gentle
    case direct
    case competitive
    /// A tone the client does not recognise. Treat as `.gentle`; never crash.
    case unknown(String)
}

// MARK: - RawRepresentable

extension ToneKey: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .gentle:         return "gentle"
        case .direct:         return "direct"
        case .competitive:    return "competitive"
        case .unknown(let s): return s
        }
    }

    /// Always succeeds — unknown strings map to `.unknown(rawValue)`.
    public init(rawValue: String) {
        switch rawValue {
        case "gentle":      self = .gentle
        case "direct":      self = .direct
        case "competitive": self = .competitive
        default:            self = .unknown(rawValue)
        }
    }
}

// MARK: - Codable

extension ToneKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ToneKey(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - CaseIterable (known cases only)

extension ToneKey: CaseIterable {
    /// The statically-known cases. `.unknown` is excluded because it has no fixed raw value.
    public static var allCases: [ToneKey] { [.gentle, .direct, .competitive] }
}
