/// A reading partner's public profile — the subset visible to other users.
///
/// Returned by `GET /book/users/{userId}/profile`. Fields the user has hidden
/// via privacy settings (P7.8) may be `nil`.
public struct PublicProfile: Codable, Sendable, Equatable {
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?
    public let avatarEmoji: String?
    public let tier: ProfileTier
    /// `nil` when the profile owner has hidden their streak (P7.8 privacy).
    public let currentStreak: Int?
    /// `nil` when the profile owner has hidden their books-finished count (P7.8 privacy).
    public let booksFinished: Int?
    public let equippedFrame: CosmeticItem?
    public let equippedTheme: CosmeticItem?
    public let badgeCount: Int
    public let joinedAt: String?

    public init(
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        avatarEmoji: String?,
        tier: ProfileTier,
        currentStreak: Int?,
        booksFinished: Int?,
        equippedFrame: CosmeticItem?,
        equippedTheme: CosmeticItem?,
        badgeCount: Int,
        joinedAt: String?
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.avatarEmoji = avatarEmoji
        self.tier = tier
        self.currentStreak = currentStreak
        self.booksFinished = booksFinished
        self.equippedFrame = equippedFrame
        self.equippedTheme = equippedTheme
        self.badgeCount = badgeCount
        self.joinedAt = joinedAt
    }

    /// Two-letter initials for the avatar fallback.
    public var initials: String {
        guard let name = displayName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Response envelope for `GET /book/users/{userId}/profile`.
public struct PublicProfileResponse: Codable, Sendable {
    public let profile: PublicProfile
}
