/// Which set of depth-variant keys a book uses.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Every switch over this enum must handle `.unknown` explicitly.
public enum VariantFamily: Sendable, Equatable, Hashable {
    /// Easy / Medium / Hard
    case emh
    /// Precise / Balanced / Challenging
    case pbc
    /// A family the client does not recognise. `variantKeys` returns `[]`; never crash.
    case unknown(String)

    /// The ordered variant keys for this family, shallowest first.
    /// Returns `[]` for an `.unknown` family — the caller should hide depth controls.
    public var variantKeys: [VariantKey] {
        switch self {
        case .emh:     return VariantKey.emhKeys
        case .pbc:     return VariantKey.pbcKeys
        case .unknown: return []
        }
    }

    /// The default (middle) variant for this family.
    /// Returns `.medium` as a safe fallback for an `.unknown` family.
    public var defaultVariant: VariantKey {
        switch self {
        case .emh:     return .medium
        case .pbc:     return .balanced
        case .unknown: return .medium
        }
    }
}

// MARK: - RawRepresentable

extension VariantFamily: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .emh:            return "EMH"
        case .pbc:            return "PBC"
        case .unknown(let s): return s
        }
    }

    /// Always succeeds — unknown strings map to `.unknown(rawValue)`.
    public init(rawValue: String) {
        switch rawValue {
        case "EMH": self = .emh
        case "PBC": self = .pbc
        default:    self = .unknown(rawValue)
        }
    }
}

// MARK: - Codable

extension VariantFamily: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = VariantFamily(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - CaseIterable (known cases only)

extension VariantFamily: CaseIterable {
    /// The statically-known cases. `.unknown` is excluded because it has no fixed raw value.
    public static var allCases: [VariantFamily] { [.emh, .pbc] }
}
