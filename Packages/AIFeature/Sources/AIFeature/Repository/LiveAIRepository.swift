import Networking
import Models
import CoreKit

/// Production ``AIRepository`` that calls the ChapterFlow REST API.
public actor LiveAIRepository: AIRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func askBook(
        bookId: String,
        question: String,
        selectionContext: String?,
        tone: String?
    ) async throws -> BookAskResponse {
        let endpoint = try Endpoints.askBook(
            bookId: bookId,
            question: question,
            selectionContext: selectionContext,
            tone: tone
        )
        return try await client.send(endpoint)
    }

    public func conceptGraph(bookId: String) async throws -> ConceptGraph {
        let endpoint = Endpoints.getConceptGraph(bookId: bookId)
        return try await client.send(endpoint)
    }

    public func depthRecommendation(bookId: String) async throws -> DepthRecommendation {
        let endpoint = Endpoints.getDepthRecommendation(bookId: bookId)
        return try await client.send(endpoint)
    }
}
