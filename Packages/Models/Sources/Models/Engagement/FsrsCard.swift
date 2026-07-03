import Foundation

/// FSRS spaced-repetition card state.
///
/// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
/// instead of throwing. Views should treat `.unknown` like `.new` (not yet due).
///
/// The server uses the name "review" for cards in the normal review queue; the
/// client maps this to `.due` so callers can use a natural name for the concept.
/// The decoder accepts both "review" (server canonical) and "due" (legacy).
public enum FsrsCardState: Sendable, Equatable, Hashable {
    case new
    case learning
    /// A card in the normal review queue. Server encodes this as `"review"`.
    case due
    case relearning
    /// A state the client does not recognise. Treat conservatively; never crash.
    case unknown(String)
}

extension FsrsCardState: RawRepresentable {
    /// The canonical wire value. `.due` encodes as `"review"` to match the server.
    public var rawValue: String {
        switch self {
        case .new:            return "new"
        case .learning:       return "learning"
        case .due:            return "review"
        case .relearning:     return "relearning"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "new":           self = .new
        case "learning":      self = .learning
        case "review", "due": self = .due   // server sends "review"; accept "due" for compat
        case "relearning":    self = .relearning
        default:              self = .unknown(rawValue)
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
/// Returned within `GET /book/me/reviews` and `POST /book/me/reviews/{cardId}`.
/// All FSRS scheduling fields are optional under the server-evolution contract.
public struct FsrsCard: Codable, Sendable, Identifiable {
    public let cardId: String
    public let bookId: String
    public let chapterId: String?
    public let front: String
    public let back: String
    /// ISO-8601 timestamp when the card is next due.
    public let dueAt: String?
    public let stability: Double?
    public let difficulty: Double?
    public let state: FsrsCardState?
    /// ISO-8601 timestamp of the last review.
    public let lastReviewAt: String?
    /// Number of times this card has been reviewed.
    public let reps: Int?
    /// Number of lapses (Again ratings) on this card.
    public let lapses: Int?
    /// Elapsed days since the last review (server-computed).
    public let elapsedDays: Double?
    /// Scheduled days for the current interval (server-computed).
    public let scheduledDays: Int?
    /// Current retrievability in [0,1] (server-computed at fetch time).
    public let retrievability: Double?

    public var id: String { cardId }

    public init(
        cardId: String, bookId: String, chapterId: String?,
        front: String, back: String,
        dueAt: String?, stability: Double?, difficulty: Double?, state: FsrsCardState?,
        lastReviewAt: String?, reps: Int?, lapses: Int?,
        elapsedDays: Double?, scheduledDays: Int?, retrievability: Double?
    ) {
        self.cardId        = cardId
        self.bookId        = bookId
        self.chapterId     = chapterId
        self.front         = front
        self.back          = back
        self.dueAt         = dueAt
        self.stability     = stability
        self.difficulty    = difficulty
        self.state         = state
        self.lastReviewAt  = lastReviewAt
        self.reps          = reps
        self.lapses        = lapses
        self.elapsedDays   = elapsedDays
        self.scheduledDays = scheduledDays
        self.retrievability = retrievability
    }

    /// Parsed due date. Returns `nil` when `dueAt` is absent or unparseable.
    public var dueDate: Date? {
        guard let str = dueAt else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(str) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(str)
    }

    /// `true` when the card's `dueDate` is on or before `now`.
    public func isDue(now: Date = Date()) -> Bool {
        guard let due = dueDate else { return state == .new }
        return due <= now
    }
}

// MARK: - ReviewCardResponse

/// Response from `POST /book/me/reviews/{cardId}`.
public struct ReviewCardResponse: Codable, Sendable {
    public let card: FsrsCard
}

// MARK: - ReviewsResponse

/// Response from `GET /book/me/reviews`.
///
/// The server returns the due-card count as `"count"`. The decoder also
/// accepts `"dueCount"` for backward compatibility with test fixtures.
///
/// The `cards` array decodes lossily — one malformed card is dropped and
/// logged while the rest of the deck survives.
public struct ReviewsResponse: Codable, Sendable {
    public let cards: [FsrsCard]
    /// Number of due cards. Resolved from either `"count"` or `"dueCount"` in JSON.
    public let dueCount: Int

    private enum CodingKeys: String, CodingKey { case cards, count, dueCount }

    public init(cards: [FsrsCard], dueCount: Int) {
        self.cards    = cards
        self.dueCount = dueCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cards = try container.decodeLossy(FsrsCard.self, forKey: .cards)
        // Server returns "count"; test fixtures may use "dueCount".
        self.dueCount = (try? container.decode(Int.self, forKey: .count))
                     ?? (try? container.decode(Int.self, forKey: .dueCount))
                     ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cards, forKey: .cards)
        try container.encode(dueCount, forKey: .count)
    }
}
