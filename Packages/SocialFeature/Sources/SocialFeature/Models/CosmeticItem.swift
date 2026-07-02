/// A cosmetic item from the user's inventory (earned via the P5.4 shop/flow-points economy).
///
/// Equipped frames and themes are surfaced in the profile view and reader.
/// Server-evolution contract: unknown ``ItemType`` raw values decode to `.unknown(rawValue)`.
/// Views must handle `.unknown` with a safe fallback — never crash.
public struct CosmeticItem: Codable, Sendable, Identifiable, Equatable {

    /// The category of cosmetic item.
    ///
    /// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`.
    public enum ItemType: Sendable, Equatable {
        case avatarFrame
        case profileTheme
        case readerTheme
        /// An item type the client does not recognise. Render a safe default; never crash.
        case unknown(String)
    }

    public let itemId: String
    public let name: String
    public let itemType: ItemType
    public let rarity: String?

    public var id: String { itemId }

    public init(itemId: String, name: String, itemType: ItemType, rarity: String? = nil) {
        self.itemId = itemId
        self.name = name
        self.itemType = itemType
        self.rarity = rarity
    }
}

// MARK: - ItemType RawRepresentable + Codable

extension CosmeticItem.ItemType: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .avatarFrame:    return "avatar_frame"
        case .profileTheme:  return "profile_theme"
        case .readerTheme:   return "reader_theme"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "avatar_frame":   self = .avatarFrame
        case "profile_theme": self = .profileTheme
        case "reader_theme":  self = .readerTheme
        default:              self = .unknown(rawValue)
        }
    }
}

extension CosmeticItem.ItemType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = CosmeticItem.ItemType(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
