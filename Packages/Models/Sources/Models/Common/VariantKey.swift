/// Reading-depth variant keys used by the content API.
///
/// Books belong to either the EMH family (`easy`/`medium`/`hard`) or the
/// PBC family (`precise`/`balanced`/`challenging`), as indicated by
/// `BookCatalogItem.variantFamily`.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Every switch over this enum must handle `.unknown` explicitly.
public enum VariantKey: Sendable, Equatable, Hashable {
    case easy
    case medium
    case hard
    case precise
    case balanced
    case challenging
    /// A variant key the client does not recognise. Treat as unavailable; never crash.
    case unknown(String)

    /// The EMH-family keys ordered from shallowest to deepest.
    public static let emhKeys: [VariantKey] = [.easy, .medium, .hard]
    /// The PBC-family keys ordered from most accessible to most technical.
    public static let pbcKeys: [VariantKey] = [.precise, .balanced, .challenging]
}

// MARK: - RawRepresentable

extension VariantKey: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .easy:           return "easy"
        case .medium:         return "medium"
        case .hard:           return "hard"
        case .precise:        return "precise"
        case .balanced:       return "balanced"
        case .challenging:    return "challenging"
        case .unknown(let s): return s
        }
    }

    /// Always succeeds — unknown strings map to `.unknown(rawValue)`.
    public init(rawValue: String) {
        switch rawValue {
        case "easy":        self = .easy
        case "medium":      self = .medium
        case "hard":        self = .hard
        case "precise":     self = .precise
        case "balanced":    self = .balanced
        case "challenging": self = .challenging
        default:            self = .unknown(rawValue)
        }
    }
}

// MARK: - Codable

extension VariantKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = VariantKey(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - CaseIterable (known cases only)

extension VariantKey: CaseIterable {
    /// The statically-known cases. `.unknown` is excluded because it has no fixed raw value.
    public static var allCases: [VariantKey] {
        [.easy, .medium, .hard, .precise, .balanced, .challenging]
    }
}
