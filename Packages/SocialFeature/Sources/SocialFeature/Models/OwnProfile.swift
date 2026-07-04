/// The authenticated user's full profile, returned by `GET /book/me/profile`.
///
/// Includes social identity, engagement stats, and the currently equipped
/// cosmetics from the inventory — everything the profile screen needs in a single
/// API round-trip.
public struct OwnProfile: Codable, Sendable, Equatable {
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?
    /// An emoji chosen as the user's avatar (e.g. "📚"). Takes precedence over initials.
    public let avatarEmoji: String?
    public let tier: ProfileTier
    /// 0…1 fraction of progress toward the next tier.
    public let tierProgress: Double?
    public let currentStreak: Int
    public let longestStreak: Int
    public let booksFinished: Int
    public let flowPoints: Int
    public let equippedFrame: CosmeticItem?
    public let equippedTheme: CosmeticItem?
    /// Total number of badges the user has earned.
    public let badgeCount: Int
    /// ISO-8601 timestamp when the account was created.
    public let joinedAt: String?
    /// The user's privacy preferences (P7.8). `nil` when the server hasn't returned
    /// them yet; treat as ``PrivacySettings/default`` in that case.
    public let privacySettings: PrivacySettings?

    public init(
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        avatarEmoji: String?,
        tier: ProfileTier,
        tierProgress: Double?,
        currentStreak: Int,
        longestStreak: Int,
        booksFinished: Int,
        flowPoints: Int,
        equippedFrame: CosmeticItem?,
        equippedTheme: CosmeticItem?,
        badgeCount: Int,
        joinedAt: String?,
        privacySettings: PrivacySettings? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.avatarEmoji = avatarEmoji
        self.tier = tier
        self.tierProgress = tierProgress
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.booksFinished = booksFinished
        self.flowPoints = flowPoints
        self.equippedFrame = equippedFrame
        self.equippedTheme = equippedTheme
        self.badgeCount = badgeCount
        self.joinedAt = joinedAt
        self.privacySettings = privacySettings
    }

    /// Two-letter initials derived from the display name, used as the avatar fallback.
    public var initials: String {
        guard let name = displayName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Response envelope for `GET /book/me/profile`.
public struct OwnProfileResponse: Codable, Sendable {
    public let profile: OwnProfile
}

/// Fields the user may update via `PATCH /book/me/settings`.
///
/// All fields are optional — only the fields present in the encoded JSON are
/// applied by the server. Pass only the fields you want to change.
public struct UpdateSettingsBody: Encodable, Sendable, Equatable {
    public let displayName: String?
    public let avatarEmoji: String?
    /// Privacy-settings update (P7.8). When non-nil, the entire settings object
    /// is patched atomically on the server.
    public let privacySettings: PrivacySettings?

    public init(
        displayName: String? = nil,
        avatarEmoji: String? = nil,
        privacySettings: PrivacySettings? = nil
    ) {
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.privacySettings = privacySettings
    }
}

/// Minimal acknowledgement from `PATCH /book/me/settings`.
/// We re-fetch the canonical profile after a successful patch.
struct SettingsUpdateResponse: Codable, Sendable {}
