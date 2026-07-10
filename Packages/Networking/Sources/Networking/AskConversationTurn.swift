import Foundation

/// A prior Q&A exchange sent to the server for conversation threading.
///
/// Included in the body of `POST /book/books/{bookId}/ask` so the server can
/// generate coherent follow-up answers. The server ignores unknown fields.
public struct AskConversationTurn: Encodable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}
