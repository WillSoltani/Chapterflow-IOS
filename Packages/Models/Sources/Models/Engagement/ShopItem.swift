/// A single item available in the Flow-Points shop.
///
/// Items are either functional rewards (book unlocks, pro passes) or
/// cosmetics (themes, frames, seasonal decorations). The server is the
/// source of truth for ownership and equipped state — do not grant locally.
public struct ShopItem: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: ShopItemKind
    public let name: String
    public let description: String
    /// Cost in Flow Points. Zero means it can be equipped for free after purchase.
    public let cost: Int
    /// `true` if the user has already purchased this item.
    public let isOwned: Bool?
    /// `true` if this cosmetic is currently active. Always `nil` for non-cosmetics.
    public let isEquipped: Bool?
    /// Optional hex color string used to render a cosmetic preview swatch.
    public let previewColor: String?

    public init(
        id: String,
        kind: ShopItemKind,
        name: String,
        description: String,
        cost: Int,
        isOwned: Bool?,
        isEquipped: Bool?,
        previewColor: String?
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.cost = cost
        self.isOwned = isOwned
        self.isEquipped = isEquipped
        self.previewColor = previewColor
    }
}

// MARK: - ShopItemKind

/// The category of a shop item.
///
/// Every switch over this enum must handle `.unknown` explicitly — hide the
/// item or render a generic fallback rather than using `@unknown default`.
public enum ShopItemKind: Codable, Sendable, Equatable {
    case bonusBookUnlock
    case proPass7d
    case proPass30d
    case theme
    case frame
    case seasonal
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "bonus_book_unlock": self = .bonusBookUnlock
        case "pro_pass_7d":       self = .proPass7d
        case "pro_pass_30d":      self = .proPass30d
        case "theme":             self = .theme
        case "frame":             self = .frame
        case "seasonal":          self = .seasonal
        default:                  self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bonusBookUnlock: try container.encode("bonus_book_unlock")
        case .proPass7d:       try container.encode("pro_pass_7d")
        case .proPass30d:      try container.encode("pro_pass_30d")
        case .theme:           try container.encode("theme")
        case .frame:           try container.encode("frame")
        case .seasonal:        try container.encode("seasonal")
        case .unknown(let r):  try container.encode(r)
        }
    }

    /// Whether this item is a cosmetic that can be equipped.
    public var isCosmetic: Bool {
        switch self {
        case .theme, .frame, .seasonal: return true
        case .bonusBookUnlock, .proPass7d, .proPass30d: return false
        case .unknown: return false
        }
    }

    /// SF Symbol for this item kind.
    public var systemImage: String {
        switch self {
        case .bonusBookUnlock: return "book.fill"
        case .proPass7d:       return "star.fill"
        case .proPass30d:      return "crown.fill"
        case .theme:           return "paintpalette.fill"
        case .frame:           return "rectangle.inset.filled"
        case .seasonal:        return "sparkles"
        case .unknown:         return "questionmark.circle.fill"
        }
    }

    /// Known cases for display; excludes `.unknown`.
    public static let allCases: [ShopItemKind] = [
        .bonusBookUnlock, .proPass7d, .proPass30d, .theme, .frame, .seasonal,
    ]
}
