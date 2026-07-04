import Foundation

/// The reward type granted by a referral event.
///
/// Tolerant: unrecognised server values decode to `.unknown(rawValue)` — never crashes a view.
public enum ReferralRewardKind: Sendable, Equatable {
    case extraFreeSlot
    case streakShield
    case proWeek
    case proMonth
    /// An unrecognised server value. Views must show a generic fallback.
    case unknown(String)
}

extension ReferralRewardKind: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "extra_free_slot":  self = .extraFreeSlot
        case "streak_shield":    self = .streakShield
        case "pro_week":         self = .proWeek
        case "pro_month":        self = .proMonth
        default:                 self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .extraFreeSlot:    try container.encode("extra_free_slot")
        case .streakShield:     try container.encode("streak_shield")
        case .proWeek:          try container.encode("pro_week")
        case .proMonth:         try container.encode("pro_month")
        case .unknown(let raw): try container.encode(raw)
        }
    }

    /// Human-readable label shown in the rewards list.
    public var displayLabel: String {
        switch self {
        case .extraFreeSlot:    return "Extra Free Book Slot"
        case .streakShield:     return "Streak Shield"
        case .proWeek:          return "7 Days of Pro"
        case .proMonth:         return "30 Days of Pro"
        case .unknown:          return "Bonus Reward"
        }
    }

    /// SF Symbol name for this reward kind.
    public var systemImageName: String {
        switch self {
        case .extraFreeSlot:    return "books.vertical"
        case .streakShield:     return "shield.lefthalf.filled"
        case .proWeek:          return "crown"
        case .proMonth:         return "crown.fill"
        case .unknown:          return "star"
        }
    }
}

// MARK: - ReferralReward

/// A single reward the user has earned (or will earn) through referrals.
///
/// `isEarned` is server-truth — never derive reward state client-side.
public struct ReferralReward: Codable, Sendable, Equatable {
    /// The type of reward.
    public let kind: ReferralRewardKind
    /// Short display title from the server.
    public let title: String
    /// Longer human-readable description from the server.
    public let description: String
    /// ISO-8601 timestamp when the reward was granted, or `nil` if not yet earned.
    public let earnedAt: String?
    /// Whether the reward has been granted to this user.
    public let isEarned: Bool

    public init(
        kind: ReferralRewardKind,
        title: String,
        description: String,
        earnedAt: String?,
        isEarned: Bool
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.earnedAt = earnedAt
        self.isEarned = isEarned
    }
}

// MARK: - ReferralStats

/// Aggregate counts of invitations in each lifecycle stage.
public struct ReferralStats: Codable, Sendable, Equatable {
    /// Invites sent but not yet signed up.
    public let pending: Int
    /// Users who signed up via this code.
    public let activated: Int
    /// Users who activated *and* upgraded to Pro.
    public let pro: Int

    public init(pending: Int, activated: Int, pro: Int) {
        self.pending = pending
        self.activated = activated
        self.pro = pro
    }
}

// MARK: - ReferralProfile

/// The authenticated user's referral programme profile.
///
/// Returned by `GET /book/me/referrals`.  Reward state and stats are
/// server-authoritative; the client never computes or grants rewards.
public struct ReferralProfile: Codable, Sendable, Equatable {
    /// The user's unique invite code (e.g. `"ALICE42"`).
    public let code: String
    /// An optional full share URL returned by the server (HTTPS Universal Link).
    /// Falls back to `"chapterflow://ref/{code}"` when absent.
    public let shareUrl: String?
    /// Aggregated invitation statistics.
    public let stats: ReferralStats
    /// Server-provided list of rewards; decoded lossily.
    public let rewards: [ReferralReward]

    public init(
        code: String,
        shareUrl: String?,
        stats: ReferralStats,
        rewards: [ReferralReward]
    ) {
        self.code = code
        self.shareUrl = shareUrl
        self.stats = stats
        self.rewards = rewards
    }

    /// The URL to share. Uses the server-provided URL when available,
    /// otherwise constructs the custom-scheme fallback.
    public var resolvedShareURL: URL {
        if let raw = shareUrl, let url = URL(string: raw) { return url }
        return URL(string: "chapterflow://ref/\(code)")!
    }

    // Use lossy decoding for the rewards array.
    enum CodingKeys: String, CodingKey {
        case code, shareUrl, stats, rewards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        shareUrl = try container.decodeIfPresent(String.self, forKey: .shareUrl)
        stats = try container.decode(ReferralStats.self, forKey: .stats)
        rewards = (try? container.decodeLossy(ReferralReward.self, forKey: .rewards)) ?? []
    }
}

// MARK: - Response envelopes

/// Response envelope for `GET /book/me/referrals`.
public struct ReferralProfileResponse: Codable, Sendable {
    public let referral: ReferralProfile
}

// MARK: - Apply result

/// The result of a successful or failed referral code attribution.
///
/// Reward state is always re-fetched from the server after a successful apply —
/// never grant or alter entitlements client-side.
public struct ReferralApplyResult: Codable, Sendable, Equatable {
    public let success: Bool
    /// Optional server message to surface to the user (e.g. "Code applied!").
    public let message: String?

    public init(success: Bool, message: String?) {
        self.success = success
        self.message = message
    }
}

/// Response envelope for `POST /book/me/referrals/apply`.
public struct ReferralApplyResponse: Codable, Sendable {
    public let result: ReferralApplyResult
}
