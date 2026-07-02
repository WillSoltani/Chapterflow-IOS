/// A spaced-repetition review card for a chapter concept.
///
/// Both `front` and `back` are tone-keyed so the text matches the user's reading style.
public struct ReviewCard: Codable, Sendable {
    public let cardId: String?
    public let front: ToneKeyed
    public let back: ToneKeyed
    public let difficulty: String?
}
