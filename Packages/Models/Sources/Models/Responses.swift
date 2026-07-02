/// Top-level response wrappers matching the API's success envelope shapes.
/// Success bodies are raw JSON objects, not nested under a generic wrapper.

public struct CatalogResponse: Codable, Sendable {
    public let books: [BookCatalogItem]
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
