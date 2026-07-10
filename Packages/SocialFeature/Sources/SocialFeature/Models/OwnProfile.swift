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

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // Only `userId` is required; stats default to 0 (the profile screen
    // overlays live stats from the dashboard/streak/points endpoints).

    private enum WireKeys: String, CodingKey {
        case userId, displayName, avatarUrl, avatarEmoji
        case tier, tierProgress, currentStreak, longestStreak
        case booksFinished, flowPoints, equippedFrame, equippedTheme
        case badgeCount, joinedAt, privacySettings
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        userId = try c.decodeRequiredFirst(String.self, keys: [.userId])
        displayName = c.decodeFirst(String.self, keys: [.displayName])
        avatarUrl = c.decodeFirst(String.self, keys: [.avatarUrl])
        avatarEmoji = c.decodeFirst(String.self, keys: [.avatarEmoji])
        tier = c.decodeFirst(ProfileTier.self, keys: [.tier]) ?? .reader
        tierProgress = c.decodeFirst(Double.self, keys: [.tierProgress])
        currentStreak = c.decodeFirst(Int.self, keys: [.currentStreak]) ?? 0
        longestStreak = c.decodeFirst(Int.self, keys: [.longestStreak]) ?? 0
        booksFinished = c.decodeFirst(Int.self, keys: [.booksFinished]) ?? 0
        flowPoints = c.decodeFirst(Int.self, keys: [.flowPoints]) ?? 0
        equippedFrame = c.decodeFirst(CosmeticItem.self, keys: [.equippedFrame])
        equippedTheme = c.decodeFirst(CosmeticItem.self, keys: [.equippedTheme])
        badgeCount = c.decodeFirst(Int.self, keys: [.badgeCount]) ?? 0
        joinedAt = c.decodeFirst(String.self, keys: [.joinedAt])
        privacySettings = c.decodeFirst(PrivacySettings.self, keys: [.privacySettings])
    }
}

/// Response envelope for `GET /book/me/profile`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route returns `{profile: <settings>|null, identity: {sub,
/// displayName, …}, inferredLocation, updatedAt}` — the `profile` object is
/// the user's PROFILE SETTINGS (may be null for a fresh account), and the
/// canonical identity lives under `identity`. When the canonical
/// `{profile: OwnProfile}` shape doesn't decode, this adapter synthesizes the
/// profile from `identity.sub` + whatever settings exist; stats default to 0
/// and are overlaid from the engagement endpoints by the profile screen.
public struct OwnProfileResponse: Codable, Sendable {
    public let profile: OwnProfile

    public init(profile: OwnProfile) {
        self.profile = profile
    }

    private enum WireKeys: String, CodingKey { case profile, identity }
    private enum IdentityK: String, CodingKey { case sub, displayName }
    private enum SettingsK: String, CodingKey { case displayName, avatarEmoji, avatarUrl }

    public init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: WireKeys.self)
        // Canonical: {profile: {userId, …}}.
        if let canonical = ((try? root.decodeIfPresent(OwnProfile.self, forKey: .profile)) ?? nil) {
            self.profile = canonical
            return
        }
        // Deployed: synthesize from identity + optional settings.
        let identity = try root.nestedContainer(keyedBy: IdentityK.self, forKey: .identity)
        let sub = try identity.decode(String.self, forKey: .sub)
        let identityName = ((try? identity.decodeIfPresent(String.self, forKey: .displayName)) ?? nil)
        let settings = try? root.nestedContainer(keyedBy: SettingsK.self, forKey: .profile)
        let settingsName = settings.flatMap {
            ((try? $0.decodeIfPresent(String.self, forKey: .displayName)) ?? nil)
        }
        self.profile = OwnProfile(
            userId: sub,
            displayName: settingsName ?? identityName,
            avatarUrl: settings.flatMap {
                ((try? $0.decodeIfPresent(String.self, forKey: .avatarUrl)) ?? nil)
            },
            avatarEmoji: settings.flatMap {
                ((try? $0.decodeIfPresent(String.self, forKey: .avatarEmoji)) ?? nil)
            },
            tier: .reader,
            tierProgress: nil,
            currentStreak: 0,
            longestStreak: 0,
            booksFinished: 0,
            flowPoints: 0,
            equippedFrame: nil,
            equippedTheme: nil,
            badgeCount: 0,
            joinedAt: nil,
            privacySettings: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: WireKeys.self)
        try root.encode(profile, forKey: .profile)
    }
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
