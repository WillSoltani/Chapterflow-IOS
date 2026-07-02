import Foundation

/// The success response from `POST /book/books/{bookId}/ask`.
///
/// `remainingQuestions` is optional because the server may not always include it;
/// the UI shows it only when present.
public struct BookAskResponse: Decodable, Sendable {
    /// The AI-generated answer text (may contain Markdown inline syntax).
    public let answer: String
    /// Chapter numbers cited as evidence for the answer.
    public let citations: [Int]
    /// How many questions the user may still ask today, when the server includes this.
    public let remainingQuestions: Int?
}
