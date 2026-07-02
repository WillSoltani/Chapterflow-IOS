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
}

public struct BadgesResponse: Codable, Sendable {
    public let badges: [BadgeItem]
}
