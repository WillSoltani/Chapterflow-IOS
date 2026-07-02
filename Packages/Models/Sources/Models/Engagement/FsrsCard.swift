/// FSRS spaced-repetition card state.
public enum FsrsCardState: String, Codable, Sendable {
    case new
    case learning
    case due
    case relearning
}

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

public struct ReviewsResponse: Codable, Sendable {
    public let cards: [FsrsCard]
    public let dueCount: Int
}
