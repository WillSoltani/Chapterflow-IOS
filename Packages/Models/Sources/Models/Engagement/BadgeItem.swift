/// An achievement badge earned (or earnable) by the user.
///
/// Returned within `GET /book/me/badges`.
public struct BadgeItem: Codable, Sendable, Identifiable {
    public let badgeId: String
    public let name: String
    public let description: String
    public let category: String
    public let isEarned: Bool
    public let earnedAt: String?
    public let icon: String?
    /// Current progress toward earning the badge (server-optional).
    public let progress: Int?
    /// Target value required to earn the badge (server-optional).
    public let target: Int?

    public var id: String { badgeId }

    public init(
        badgeId: String,
        name: String,
        description: String,
        category: String,
        isEarned: Bool,
        earnedAt: String?,
        icon: String?,
        progress: Int? = nil,
        target: Int? = nil
    ) {
        self.badgeId = badgeId
        self.name = name
        self.description = description
        self.category = category
        self.isEarned = isEarned
        self.earnedAt = earnedAt
        self.icon = icon
        self.progress = progress
        self.target = target
    }

    /// 0–1 fraction toward earning the badge; `nil` when progress data is absent.
    public var progressFraction: Double? {
        guard let p = progress, let t = target, t > 0 else { return nil }
        return min(1.0, Double(p) / Double(t))
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // The deployed /book/me/badges returns EARNED award records
    // ({badgeId, earnedAt, tier?…}) without name/description/category. Only
    // `badgeId` is required; display fields default (name falls back to the
    // id) and `isEarned` is inferred from `earnedAt` when absent.

    private enum WireKeys: String, CodingKey {
        case badgeId, name, description, category
        case isEarned, earnedAt, icon, progress, target
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        badgeId = try c.decodeRequiredFirst(String.self, keys: [.badgeId])
        name = c.decodeFirst(String.self, keys: [.name]) ?? badgeId
        description = c.decodeFirst(String.self, keys: [.description]) ?? ""
        category = c.decodeFirst(String.self, keys: [.category]) ?? "achievement"
        earnedAt = c.decodeFirst(String.self, keys: [.earnedAt])
        isEarned = c.decodeFirst(Bool.self, keys: [.isEarned]) ?? (earnedAt != nil)
        icon = c.decodeFirst(String.self, keys: [.icon])
        progress = c.decodeFirst(Int.self, keys: [.progress])
        target = c.decodeFirst(Int.self, keys: [.target])
    }
}

/// Response from `GET /book/me/badges`.
/// Decodes the array lossily — one malformed badge is dropped and logged
/// while the rest of the collection survives.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route keys the list `awards`; the canonical shape is `badges`.
/// Both decode; encoding stays canonical.
public struct BadgesResponse: Codable, Sendable {
    public let badges: [BadgeItem]

    private enum CodingKeys: String, CodingKey { case badges, awards }

    public init(badges: [BadgeItem]) {
        self.badges = badges
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.badges) {
            self.badges = try container.decodeLossy(BadgeItem.self, forKey: .badges)
        } else if container.contains(.awards) {
            self.badges = try container.decodeLossy(BadgeItem.self, forKey: .awards)
        } else {
            self.badges = []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(badges, forKey: .badges)
    }
}
