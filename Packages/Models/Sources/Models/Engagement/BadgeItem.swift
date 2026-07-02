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

    public var id: String { badgeId }

    public init(
        badgeId: String,
        name: String,
        description: String,
        category: String,
        isEarned: Bool,
        earnedAt: String?,
        icon: String?
    ) {
        self.badgeId = badgeId
        self.name = name
        self.description = description
        self.category = category
        self.isEarned = isEarned
        self.earnedAt = earnedAt
        self.icon = icon
    }
}

/// Response from `GET /book/me/badges`.
/// Decodes the `badges` array lossily — one malformed badge is dropped and
/// logged while the rest of the collection survives.
public struct BadgesResponse: Codable, Sendable {
    public let badges: [BadgeItem]

    private enum CodingKeys: String, CodingKey { case badges }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.badges = try container.decodeLossy(BadgeItem.self, forKey: .badges)
    }
}
