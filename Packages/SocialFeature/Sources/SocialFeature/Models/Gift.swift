import Foundation

/// A shareable gift code that grants a recipient Pro access for one week.
///
/// Returned by `GET /book/me/gifts/{code}` (preview before claiming) and
/// `POST /book/me/gifts` (newly created gift) and referenced after
/// `POST /book/me/gifts/{code}/claim`.
public struct Gift: Codable, Sendable, Equatable {
    public let code: String
    /// The product granted (e.g. `"pro_week"`).
    public let giftType: String
    /// Display name of the user who created this gift, if provided by the server.
    public let senderDisplayName: String?
    public let status: GiftStatus
    /// ISO-8601 creation timestamp.
    public let createdAt: String?
    /// ISO-8601 expiry timestamp; nil means no expiry.
    public let expiresAt: String?

    public init(
        code: String,
        giftType: String,
        senderDisplayName: String?,
        status: GiftStatus,
        createdAt: String?,
        expiresAt: String?
    ) {
        self.code = code
        self.giftType = giftType
        self.senderDisplayName = senderDisplayName
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// A short human-readable description of what this gift grants.
    public var giftTypeLabel: String {
        switch giftType.lowercased() {
        case "pro_week":  return "1 Week of Pro"
        case "pro_month": return "1 Month of Pro"
        default:          return giftType
        }
    }
}

/// The lifecycle state of a gift code.
///
/// Tolerant: unrecognised server values map to `.unknown(rawValue)` — never crashes a view.
public enum GiftStatus: Sendable, Equatable {
    case pending
    case claimed
    case expired
    /// An unrecognised server value. Views must handle this with a sensible fallback.
    case unknown(String)
}

extension GiftStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "pending": self = .pending
        case "claimed": self = .claimed
        case "expired": self = .expired
        default:        self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pending:         try container.encode("pending")
        case .claimed:         try container.encode("claimed")
        case .expired:         try container.encode("expired")
        case .unknown(let r):  try container.encode(r)
        }
    }
}

// MARK: - Response envelopes

/// Response envelope for `GET /book/me/gifts/{code}`.
public struct GiftPreviewResponse: Codable, Sendable {
    public let gift: Gift
}

/// Response envelope for `POST /book/me/gifts` (create).
public struct CreateGiftResponse: Codable, Sendable {
    public let gift: Gift
}

/// Response envelope for `POST /book/me/gifts/{code}/claim`.
///
/// Always re-fetch `/book/me/entitlements` after a successful claim —
/// never grant Pro client-side.
public struct GiftClaimResponse: Codable, Sendable {
    public let gift: Gift
    /// Optional human-readable confirmation from the server.
    public let message: String?
}

// MARK: - Domain result

/// The result of a successful gift claim, combining the claimed gift and
/// any server confirmation message.
public struct GiftClaimResult: Sendable, Equatable {
    public let gift: Gift
    public let message: String?

    public init(gift: Gift, message: String?) {
        self.gift = gift
        self.message = message
    }
}
