/// FSRS spaced-repetition card state.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views should treat `.unknown` like `.new` (not yet due).
public enum FsrsCardState: Sendable, Equatable, Hashable {
    case new
    case learning
    case due
    case relearning
    /// A state the client does not recognise. Treat conservatively; never crash.
    case unknown(String)
}

extension FsrsCardState: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .new:            return "new"
        case .learning:       return "learning"
        case .due:            return "due"
        case .relearning:     return "relearning"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "new":        self = .new
        case "learning":   self = .learning
        case "due":        self = .due
        case "relearning": self = .relearning
        default:           self = .unknown(rawValue)
        }
    }
}

extension FsrsCardState: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = FsrsCardState(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension FsrsCardState: CaseIterable {
    public static var allCases: [FsrsCardState] { [.new, .learning, .due, .relearning] }
}

// MARK: - FsrsCard

/// A spaced-repetition review card in the user's deck, with FSRS scheduling data.
///
/// Returned within `GET /book/me/reviews`.
public struct FsrsCard: Codable, Sendable, Identifiable {
    public let cardId: String
    public let bookId: String
    public let chapterId: String?
    public let front: String
    public let back: String
    public let dueAt: String?
    public let stability: Double?
    public let difficulty: Double?
    public let state: FsrsCardState?

    public var id: String { cardId }
}

// MARK: - ReviewsResponse

/// Response from `GET /book/me/reviews`.
/// Decodes the `cards` array lossily — one malformed card is dropped and
/// logged while the rest of the deck survives.
public struct ReviewsResponse: Codable, Sendable {
    public let cards: [FsrsCard]
    public let dueCount: Int

    private enum CodingKeys: String, CodingKey { case cards, dueCount }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cards = try container.decodeLossy(FsrsCard.self, forKey: .cards)
        self.dueCount = try container.decode(Int.self, forKey: .dueCount)
    }
}
