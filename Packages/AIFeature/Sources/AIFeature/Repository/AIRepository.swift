import Models

/// A single prior Q&A exchange sent to the server for conversation threading.
///
/// Included in the body of `POST /book/books/{bookId}/ask` so the server can
/// generate coherent follow-up answers. Up to the last 5 turns are sent.
public struct AIConversationTurn: Codable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// The data contract for the AI features lane (P6.*).
///
/// Concrete implementations: ``LiveAIRepository`` (production) and
/// ``FakeAIRepository`` (tests and previews).
public protocol AIRepository: Sendable {
    /// Immutable account authority used to key private conversation state.
    nonisolated var accountID: String { get }

    /// Sends a question about the given book to the server.
    ///
    /// - Parameters:
    ///   - bookId: The book being asked about.
    ///   - question: The user's question.
    ///   - selectionContext: Optional highlighted passage that grounds the answer.
    ///   - tone: Optional reading-tone raw value (`"gentle"`, `"direct"`, `"competitive"`).
    ///   - conversationHistory: Prior Q&A turns to give the server conversation context.
    ///     Pass the last few exchanges so follow-up questions are coherent. Nil → fresh question.
    /// - Throws: `AppError.rateLimited` on HTTP 429; `AppError.offline` when
    ///   there is no network; other `AppError` cases for server or auth failures.
    func askBook(
        bookId: String,
        question: String,
        selectionContext: String?,
        tone: String?,
        conversationHistory: [AIConversationTurn]?
    ) async throws -> BookAskResponse

    /// Fetches the concept dependency graph for a book.
    ///
    /// - Parameter bookId: The book whose concept graph is requested.
    /// - Returns: The full ``ConceptGraph`` (concepts, edges, chapter mappings).
    /// - Throws: `AppError.offline` when there is no network; other `AppError` cases for failures.
    func conceptGraph(bookId: String) async throws -> ConceptGraph

    /// Fetches the server's adaptive reading-depth recommendation for this user/book pair.
    ///
    /// The returned `DepthRecommendation.isConfident` flag indicates whether the server
    /// has enough data to surface the suggestion. Low-confidence results should be hidden.
    ///
    /// - Parameter bookId: The book for which to fetch a depth recommendation.
    /// - Returns: A ``DepthRecommendation`` with a recommended depth and confidence score.
    /// - Throws: `AppError.offline` when there is no network; other `AppError` cases for failures.
    func depthRecommendation(bookId: String) async throws -> DepthRecommendation
}
