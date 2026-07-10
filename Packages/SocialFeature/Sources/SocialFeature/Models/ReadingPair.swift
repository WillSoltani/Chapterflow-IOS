import Foundation
import Models

// MARK: - PairStatus

/// Lifecycle state of a reading partnership.
///
/// Uses `.unknown(String)` for forward-compatibility per RF2 — an unrecognised
/// server value must never crash a view.
public enum PairStatus: Sendable, Equatable {
    case active
    case pending
    case expired
    case unknown(String)
}

extension PairStatus: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "active":   self = .active
        case "pending":  self = .pending
        // The deployed pair records use "ended" for a finished partnership —
        // semantically our `.expired` (contract reconciliation).
        case "expired", "ended": self = .expired
        default:         self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .active:           try container.encode("active")
        case .pending:          try container.encode("pending")
        case .expired:          try container.encode("expired")
        case .unknown(let raw): try container.encode(raw)
        }
    }

    /// Human-readable label for display in the UI.
    public var displayLabel: String {
        switch self {
        case .active:         return "Active"
        case .pending:        return "Pending"
        case .expired:        return "Expired"
        case .unknown:        return "Unknown"
        }
    }
}

// MARK: - ReadingPair

/// A reading partnership between the authenticated user and one other person.
///
/// Returned in the list from `GET /book/me/pairs` and individually from
/// `GET /book/me/pairs/{partnerId}`.
public struct ReadingPair: Codable, Sendable, Identifiable {
    /// Unique partnership identifier (also the partner's user ID).
    public let partnerId: String
    public let partnerDisplayName: String?
    public let partnerAvatarUrl: String?
    public let partnerAvatarEmoji: String?
    public let partnerTier: ProfileTier
    public let partnerCurrentStreak: Int
    public let partnerBooksFinished: Int
    public let status: PairStatus
    public let pairedAt: String?

    public var id: String { partnerId }

    public init(
        partnerId: String,
        partnerDisplayName: String?,
        partnerAvatarUrl: String?,
        partnerAvatarEmoji: String?,
        partnerTier: ProfileTier,
        partnerCurrentStreak: Int,
        partnerBooksFinished: Int,
        status: PairStatus,
        pairedAt: String?
    ) {
        self.partnerId = partnerId
        self.partnerDisplayName = partnerDisplayName
        self.partnerAvatarUrl = partnerAvatarUrl
        self.partnerAvatarEmoji = partnerAvatarEmoji
        self.partnerTier = partnerTier
        self.partnerCurrentStreak = partnerCurrentStreak
        self.partnerBooksFinished = partnerBooksFinished
        self.status = status
        self.pairedAt = pairedAt
    }

    /// Two-letter initials for the avatar fallback.
    public var initials: String {
        guard let name = partnerDisplayName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // Only `partnerId` is required; the deployed pair record carries no
    // partner stats (they arrive in a separate `partner` summary — merged by
    // `PairsListResponse`), so counters default to 0.

    private enum WireKeys: String, CodingKey {
        case partnerId, partnerDisplayName, partnerAvatarUrl, partnerAvatarEmoji
        case partnerTier, partnerCurrentStreak, partnerBooksFinished
        case status, pairedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        partnerId = try c.decodeRequiredFirst(String.self, keys: [.partnerId])
        partnerDisplayName = c.decodeFirst(String.self, keys: [.partnerDisplayName])
        partnerAvatarUrl = c.decodeFirst(String.self, keys: [.partnerAvatarUrl])
        partnerAvatarEmoji = c.decodeFirst(String.self, keys: [.partnerAvatarEmoji])
        partnerTier = c.decodeFirst(ProfileTier.self, keys: [.partnerTier]) ?? .reader
        partnerCurrentStreak = c.decodeFirst(Int.self, keys: [.partnerCurrentStreak]) ?? 0
        partnerBooksFinished = c.decodeFirst(Int.self, keys: [.partnerBooksFinished]) ?? 0
        status = c.decodeFirst(PairStatus.self, keys: [.status]) ?? .unknown("")
        pairedAt = c.decodeFirst(String.self, keys: [.pairedAt])
    }
}

// MARK: - PairInvite

/// The server-generated invite returned by `POST /book/me/pairs/invite`.
///
/// Contains the shareable `inviteLink` (a Universal Link) and the raw `code`
/// for the manual-entry fallback on iOS (since iOS has no deferred deep linking).
public struct PairInvite: Codable, Sendable {
    public let code: String
    public let inviteLink: String
    public let expiresAt: String?

    public init(code: String, inviteLink: String, expiresAt: String?) {
        self.code = code
        self.inviteLink = inviteLink
        self.expiresAt = expiresAt
    }
}

// MARK: - Response envelopes

/// Decodes `pairs` lossily — one malformed pair must never blank the whole
/// partners screen (contract-reconciliation trap §5.4).
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed `GET /book/me/pairs` returns a SINGLE active pairing as
/// `{pair: {partnerId, pairedAt, status, …}|null, partner: <PII-safe
/// summary>|null}` — not a list. Both shapes decode: the single form merges
/// the partner summary's display name into the one `ReadingPair`.
public struct PairsListResponse: Codable, Sendable {
    public let pairs: [ReadingPair]

    public init(pairs: [ReadingPair]) {
        self.pairs = pairs
    }

    private enum CodingKeys: String, CodingKey { case pairs, pair, partner }
    private enum PartnerK: String, CodingKey {
        case displayName, partnerDisplayName, avatarEmoji, avatarUrl
        case tier, currentStreak, booksFinished
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.pairs) {
            self.pairs = try container.decodeLossy(ReadingPair.self, forKey: .pairs)
            return
        }
        // Deployed single-pair shape.
        guard let base = ((try? container.decodeIfPresent(ReadingPair.self, forKey: .pair)) ?? nil)
        else {
            self.pairs = []
            return
        }
        if let partner = try? container.nestedContainer(keyedBy: PartnerK.self, forKey: .partner) {
            self.pairs = [
                ReadingPair(
                    partnerId: base.partnerId,
                    partnerDisplayName: partner.decodeFirst(
                        String.self, keys: [.displayName, .partnerDisplayName])
                        ?? base.partnerDisplayName,
                    partnerAvatarUrl: partner.decodeFirst(String.self, keys: [.avatarUrl])
                        ?? base.partnerAvatarUrl,
                    partnerAvatarEmoji: partner.decodeFirst(String.self, keys: [.avatarEmoji])
                        ?? base.partnerAvatarEmoji,
                    partnerTier: partner.decodeFirst(ProfileTier.self, keys: [.tier])
                        ?? base.partnerTier,
                    partnerCurrentStreak: partner.decodeFirst(Int.self, keys: [.currentStreak])
                        ?? base.partnerCurrentStreak,
                    partnerBooksFinished: partner.decodeFirst(Int.self, keys: [.booksFinished])
                        ?? base.partnerBooksFinished,
                    status: base.status,
                    pairedAt: base.pairedAt)
            ]
        } else {
            self.pairs = [base]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pairs, forKey: .pairs)
    }
}

public struct PairResponse: Codable, Sendable {
    public let pair: ReadingPair
}

public struct PairInviteResponse: Codable, Sendable {
    public let code: String
    public let inviteLink: String
    public let expiresAt: String?

    public var invite: PairInvite {
        PairInvite(code: code, inviteLink: inviteLink, expiresAt: expiresAt)
    }
}

/// Acknowledgement returned after a nudge or delete (may carry no payload).
public struct PairAckResponse: Codable, Sendable {
    public let success: Bool?
}
