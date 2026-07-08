import Models

// MARK: - Card type

/// The kind of achievement being shared. Server-evolution contract: unknown raw
/// values decode to `.unknown(rawValue)` — never crash a share flow.
public enum ShareCardType: Sendable, Equatable {
    case chapter
    case badge
    case streak
    case book
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .chapter:          return "chapter"
        case .badge:            return "badge"
        case .streak:           return "streak"
        case .book:             return "book"
        case .unknown(let s):   return s
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "chapter":  self = .chapter
        case "badge":    self = .badge
        case "streak":   self = .streak
        case "book":     self = .book
        default:         self = .unknown(rawValue)
        }
    }
}

extension ShareCardType: RawRepresentable {}

extension ShareCardType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ShareCardType(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Share destination

/// The surface/platform where the user chose to share. Server-evolution: unknown
/// raw values map to `.unknown(rawValue)`.
public enum ShareEventDestination: Sendable, Equatable {
    case instagram
    case twitter
    case messages
    case other
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .instagram:        return "instagram"
        case .twitter:          return "twitter"
        case .messages:         return "messages"
        case .other:            return "other"
        case .unknown(let s):   return s
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "instagram":  self = .instagram
        case "twitter":    self = .twitter
        case "messages":   self = .messages
        case "other":      self = .other
        default:           self = .unknown(rawValue)
        }
    }
}

extension ShareEventDestination: RawRepresentable {}

extension ShareEventDestination: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ShareEventDestination(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Request / response

/// POST body for `POST /book/me/share-events`.
public struct ShareEventBody: Encodable, Sendable, Equatable {
    public let cardType: String
    public let destination: String

    public init(cardType: ShareCardType, destination: ShareEventDestination) {
        self.cardType = cardType.rawValue
        self.destination = destination.rawValue
    }
}

/// Minimal acknowledgement returned by `POST /book/me/share-events`.
public struct ShareEventResponse: Codable, Sendable {
    public let success: Bool?

    public init(success: Bool?) {
        self.success = success
    }
}

// MARK: - Card render input

/// Typed input for rendering each share card variant.
///
/// Carries only the data the card view needs — no network types, no UI state.
/// The referral code is embedded as an optional string; when absent the card
/// renders without a personal referral link (graceful degradation).
public enum ShareCardInput: Sendable, Equatable {
    /// A completed chapter.
    case chapter(
        bookTitle: String,
        bookEmoji: String,
        chapterNumber: Int,
        chapterTitle: String,
        userName: String?,
        tier: ProfileTier,
        referralCode: String?
    )

    /// An earned badge.
    case badge(
        badgeName: String,
        badgeDescription: String,
        badgeIcon: String?,
        category: String,
        userName: String?,
        tier: ProfileTier,
        referralCode: String?
    )

    /// A streak milestone.
    case streak(
        days: Int,
        userName: String?,
        tier: ProfileTier,
        referralCode: String?
    )

    /// A completed book.
    case book(
        bookTitle: String,
        bookEmoji: String,
        authorName: String?,
        totalChapters: Int,
        userName: String?,
        tier: ProfileTier,
        referralCode: String?
    )

    /// The `ShareCardType` corresponding to this input.
    public var cardType: ShareCardType {
        switch self {
        case .chapter: return .chapter
        case .badge:   return .badge
        case .streak:  return .streak
        case .book:    return .book
        }
    }

    /// The referral link to embed in the card, if a code is available.
    public var referralLink: String? {
        guard let code = referralCode else { return nil }
        return "app.chapterflow.ca/ref/\(code)"
    }

    private var referralCode: String? {
        switch self {
        case .chapter(_, _, _, _, _, _, let code):  return code
        case .badge(_, _, _, _, _, _, let code):    return code
        case .streak(_, _, _, let code):            return code
        case .book(_, _, _, _, _, _, let code):     return code
        }
    }
}
