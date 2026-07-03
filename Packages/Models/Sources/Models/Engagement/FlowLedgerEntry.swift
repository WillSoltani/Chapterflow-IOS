import Foundation

/// A single transaction in the user's Flow-Points ledger.
///
/// Returned as part of `GET /book/me/flow-points`.
public struct FlowLedgerEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let type: FlowLedgerEntryType
    /// Signed point amount: positive = earned, negative = spent.
    public let amount: Int
    /// Human-readable description from the server.
    public let description: String
    /// ISO-8601 timestamp.
    public let createdAt: String

    public init(
        id: String,
        type: FlowLedgerEntryType,
        amount: Int,
        description: String,
        createdAt: String
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.description = description
        self.createdAt = createdAt
    }
}

// MARK: - FlowLedgerEntryType

/// The kind of event that generated a Flow-Points transaction.
///
/// Every switch over this enum must handle `.unknown` explicitly — use a
/// generic icon / description rather than `@unknown default`.
public enum FlowLedgerEntryType: Codable, Sendable, Equatable {
    case earnDaily
    case earnQuiz
    case earnMilestone
    case earnStreak
    case redeem
    case adjustment
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "earn_daily":     self = .earnDaily
        case "earn_quiz":      self = .earnQuiz
        case "earn_milestone": self = .earnMilestone
        case "earn_streak":    self = .earnStreak
        case "redeem":         self = .redeem
        case "adjustment":     self = .adjustment
        default:               self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .earnDaily:     try container.encode("earn_daily")
        case .earnQuiz:      try container.encode("earn_quiz")
        case .earnMilestone: try container.encode("earn_milestone")
        case .earnStreak:    try container.encode("earn_streak")
        case .redeem:        try container.encode("redeem")
        case .adjustment:    try container.encode("adjustment")
        case .unknown(let r): try container.encode(r)
        }
    }

    /// SF Symbol for this transaction type.
    public var systemImage: String {
        switch self {
        case .earnDaily:     return "sun.max.fill"
        case .earnQuiz:      return "checkmark.seal.fill"
        case .earnMilestone: return "flag.checkered"
        case .earnStreak:    return "flame.fill"
        case .redeem:        return "storefront.fill"
        case .adjustment:    return "slider.horizontal.3"
        case .unknown:       return "circle.fill"
        }
    }

    /// Known cases for iteration / display; excludes `.unknown`.
    public static let allCases: [FlowLedgerEntryType] = [
        .earnDaily, .earnQuiz, .earnMilestone, .earnStreak, .redeem, .adjustment,
    ]
}
