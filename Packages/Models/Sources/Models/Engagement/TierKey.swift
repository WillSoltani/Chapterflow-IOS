/// The tier a user has reached in their learning journey.
///
/// Raw values match the server's lowercase string representation.
/// An unknown tier from a future server version decodes to `.unknown(String)`
/// instead of throwing — an unrecognised tier must never crash a view.
public enum TierKey: Sendable, Hashable {

    case reader
    case analyst
    case synthesizer
    case polymath
    case luminary
    /// A tier the client does not yet know about; never crash, always show a safe fallback.
    case unknown(String)

    // MARK: - Known cases (excludes .unknown per RF2 convention)

    public static let allCases: [TierKey] = [
        .reader, .analyst, .synthesizer, .polymath, .luminary
    ]

    // MARK: - Raw value

    public var rawValue: String {
        switch self {
        case .reader:          return "reader"
        case .analyst:         return "analyst"
        case .synthesizer:     return "synthesizer"
        case .polymath:        return "polymath"
        case .luminary:        return "luminary"
        case .unknown(let s):  return s
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "reader":      self = .reader
        case "analyst":     self = .analyst
        case "synthesizer": self = .synthesizer
        case "polymath":    self = .polymath
        case "luminary":    self = .luminary
        default:            self = .unknown(rawValue)
        }
    }

    // MARK: - Ordinal rank (for comparison; .unknown is treated as peer to .luminary)

    /// Ordinal rank within the known tier sequence (0 = reader, 4 = luminary).
    /// Returns `Int.max` for `.unknown` so the view degrades gracefully.
    public var rank: Int {
        switch self {
        case .reader:      return 0
        case .analyst:     return 1
        case .synthesizer: return 2
        case .polymath:    return 3
        case .luminary:    return 4
        case .unknown:     return Int.max
        }
    }
}

// MARK: - Codable

extension TierKey: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TierKey(rawValue: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
