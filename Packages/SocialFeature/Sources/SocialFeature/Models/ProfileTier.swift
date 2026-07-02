/// The user's progression tier within ChapterFlow.
///
/// Tiers progress reader → analyst → synthesizer → polymath → luminary,
/// reflecting accumulated learning depth. Server-evolution contract: unknown raw
/// values decode to `.unknown(rawValue)` — never crash a profile view.
public enum ProfileTier: Sendable, Equatable {
    case reader
    case analyst
    case synthesizer
    case polymath
    case luminary
    /// A tier the client does not recognise. Treat as `.reader`; never crash.
    case unknown(String)

    /// A localised display label suitable for profile badges and cards.
    public var displayLabel: String {
        switch self {
        case .reader:       return "Reader"
        case .analyst:      return "Analyst"
        case .synthesizer:  return "Synthesizer"
        case .polymath:     return "Polymath"
        case .luminary:     return "Luminary"
        case .unknown:      return "Reader"
        }
    }

    /// A SF Symbol name that represents the tier visually.
    public var systemImageName: String {
        switch self {
        case .reader:       return "book.circle"
        case .analyst:      return "magnifyingglass.circle"
        case .synthesizer:  return "wand.and.stars"
        case .polymath:     return "brain.head.profile"
        case .luminary:     return "sparkles"
        case .unknown:      return "book.circle"
        }
    }
}

// MARK: - RawRepresentable + Codable

extension ProfileTier: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .reader:           return "reader"
        case .analyst:          return "analyst"
        case .synthesizer:      return "synthesizer"
        case .polymath:         return "polymath"
        case .luminary:         return "luminary"
        case .unknown(let s):   return s
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "reader":       self = .reader
        case "analyst":      self = .analyst
        case "synthesizer":  self = .synthesizer
        case "polymath":     self = .polymath
        case "luminary":     self = .luminary
        default:             self = .unknown(rawValue)
        }
    }
}

extension ProfileTier: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ProfileTier(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
