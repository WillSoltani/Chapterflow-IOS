/// Top-level response wrappers matching the API's success envelope shapes.
/// Success bodies are raw JSON objects, not nested under a generic wrapper.

/// Decodes the `books` array lossily — one malformed book is dropped and
/// logged while the rest of the catalog survives.
public struct CatalogResponse: Codable, Sendable {
    public let books: [BookCatalogItem]

    private enum CodingKeys: String, CodingKey { case books }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.books = try container.decodeLossy(BookCatalogItem.self, forKey: .books)
    }
}

public struct ChapterResponse: Codable, Sendable {
    public let chapter: Chapter
    public let progress: BookProgress
}

public struct QuizResponse: Codable, Sendable {
    public let quiz: QuizClientSession
    public let progress: BookProgress
}

public struct EntitlementResponse: Codable, Sendable {
    public let entitlement: Entitlement
    public let paywall: Paywall?
}

public struct BookStateResponseEnvelope: Codable, Sendable {
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?
}
