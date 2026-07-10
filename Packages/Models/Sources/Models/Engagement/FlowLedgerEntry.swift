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

    // MARK: - Wire-shape tolerance (contract reconciliation)
    // Deployed `recentTransactions` entries are shaped
    // {transactionId, direction: "earn"|"spend", amount, sourceType, title,
    //  subtitle, createdAt} — the id/type/description keys differ and the
    // amount's sign comes from `direction`.

    private enum WireKeys: String, CodingKey {
        case id, transactionId
        case type, sourceType
        case amount, direction
        case description, title, subtitle
        case createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        id = try c.decodeRequiredFirst(String.self, keys: [.id, .transactionId])
        type = c.decodeFirst(FlowLedgerEntryType.self, keys: [.type, .sourceType])
            ?? .unknown("")
        let rawAmount = c.decodeFirst(Int.self, keys: [.amount]) ?? 0
        if let direction = c.decodeFirst(String.self, keys: [.direction]),
           direction.lowercased() == "spend" {
            amount = -abs(rawAmount)
        } else {
            amount = rawAmount
        }
        description = c.decodeFirst(String.self, keys: [.description, .title, .subtitle]) ?? ""
        createdAt = c.decodeFirst(String.self, keys: [.createdAt]) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(amount, forKey: .amount)
        try c.encode(description, forKey: .description)
        try c.encode(createdAt, forKey: .createdAt)
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
