/// Which set of depth-variant keys a book uses.
public enum VariantFamily: String, Codable, Sendable, CaseIterable, Equatable {
    /// Easy / Medium / Hard
    case emh = "EMH"
    /// Precise / Balanced / Challenging
    case pbc = "PBC"

    /// The ordered variant keys for this family, shallowest first.
    public var variantKeys: [VariantKey] {
        switch self {
        case .emh: return VariantKey.emhKeys
        case .pbc: return VariantKey.pbcKeys
        }
    }

    /// The default (middle) variant for this family.
    public var defaultVariant: VariantKey {
        switch self {
        case .emh: return .medium
        case .pbc: return .balanced
        }
    }
}
