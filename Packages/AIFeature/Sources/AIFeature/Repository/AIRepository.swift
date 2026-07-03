import Models

/// The data contract for the AI features lane (P6.*).
///
/// Concrete implementations: ``LiveAIRepository`` (production) and
/// ``FakeAIRepository`` (tests and previews).
public protocol AIRepository: Sendable {
    /// Sends a question about the given book to the server.
    ///
    /// - Parameters:
    ///   - bookId: The book being asked about.
    ///   - question: The user's question.
    ///   - selectionContext: Optional highlighted passage that grounds the answer.
    ///   - tone: Optional reading-tone raw value (`"gentle"`, `"direct"`, `"competitive"`).
    /// - Throws: `AppError.rateLimited` on HTTP 429; `AppError.offline` when
    ///   there is no network; other `AppError` cases for server or auth failures.
    func askBook(
        bookId: String,
        question: String,
        selectionContext: String?,
        tone: String?
    ) async throws -> BookAskResponse

    /// Fetches the concept dependency graph for a book.
    ///
    /// - Parameter bookId: The book whose concept graph is requested.
    /// - Returns: The full ``ConceptGraph`` (concepts, edges, chapter mappings).
    /// - Throws: `AppError.offline` when there is no network; other `AppError` cases for failures.
    func conceptGraph(bookId: String) async throws -> ConceptGraph
}
