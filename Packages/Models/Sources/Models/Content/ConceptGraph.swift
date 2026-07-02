/// A concept dependency graph for a book.
///
/// Returned by `GET /book/books/{bookId}/concept-graph`.
public struct ConceptGraph: Codable, Sendable {
    public let concepts: [ConceptNode]
    public let edges: [ConceptEdge]
    public let chapterIntroduces: [String: [String]]?
    public let chapterRequires: [String: [String]]?
}

/// A single concept node in the graph.
public struct ConceptNode: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let introducedIn: String?
    public let summary: String?
}

/// A directed relationship between two concept nodes.
public struct ConceptEdge: Codable, Sendable {
    public let from: String
    public let to: String
    public let type: String
}
