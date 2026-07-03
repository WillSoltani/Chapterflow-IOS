/// A concept dependency graph for a book.
///
/// Returned by `GET /book/books/{bookId}/concept-graph`.
public struct ConceptGraph: Codable, Sendable {
    public let concepts: [ConceptNode]
    public let edges: [ConceptEdge]
    public let chapterIntroduces: [String: [String]]?
    public let chapterRequires: [String: [String]]?

    public init(
        concepts: [ConceptNode],
        edges: [ConceptEdge],
        chapterIntroduces: [String: [String]]? = nil,
        chapterRequires: [String: [String]]? = nil
    ) {
        self.concepts = concepts
        self.edges = edges
        self.chapterIntroduces = chapterIntroduces
        self.chapterRequires = chapterRequires
    }
}

/// A single concept node in the graph.
public struct ConceptNode: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let introducedIn: String?
    public let summary: String?

    public init(id: String, label: String, introducedIn: String? = nil, summary: String? = nil) {
        self.id = id
        self.label = label
        self.introducedIn = introducedIn
        self.summary = summary
    }
}

/// The relationship type of a directed concept edge.
///
/// The `from` node is a prerequisite of the `to` node (learn `from` before `to`).
/// Tolerant: unknown server edge types decode to `.unknown(rawValue)` and must never crash a view.
public enum EdgeType: Sendable, Equatable {
    case prerequisite
    case unknown(String)
}

extension EdgeType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "prerequisite":
            self = .prerequisite
        default:
            self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .prerequisite:
            try container.encode("prerequisite")
        case .unknown(let raw):
            try container.encode(raw)
        }
    }
}

/// A directed relationship between two concept nodes.
///
/// `from` is a prerequisite of `to`: learn `from` before `to`.
/// `edgeType` is tolerant — unknown server values map to `.unknown(rawValue)`.
public struct ConceptEdge: Codable, Sendable {
    public let from: String
    public let to: String
    public let edgeType: EdgeType

    public init(from: String, to: String, edgeType: EdgeType) {
        self.from = from
        self.to = to
        self.edgeType = edgeType
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case to
        case edgeType = "type"
    }
}
