/// Reading-depth variant keys used by the content API.
///
/// Books belong to either the EMH family (`easy`/`medium`/`hard`) or the
/// PBC family (`precise`/`balanced`/`challenging`), as indicated by
/// `BookCatalogItem.variantFamily`.
public enum VariantKey: String, Codable, Sendable, CaseIterable, Equatable {
    case easy
    case medium
    case hard
    case precise
    case balanced
    case challenging

    /// The EMH-family keys ordered from shallowest to deepest.
    public static let emhKeys: [VariantKey] = [.easy, .medium, .hard]
    /// The PBC-family keys ordered from most accessible to most technical.
    public static let pbcKeys: [VariantKey] = [.precise, .balanced, .challenging]
}
