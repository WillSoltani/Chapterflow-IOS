import Foundation
import Models
import Networking

/// Production ``BookDetailRepository`` that fetches from the ChapterFlow REST API.
public actor LiveBookDetailRepository: BookDetailRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func getBook(id: String) async throws -> BookManifest {
        try await client.send(Endpoints.getBook(id: id))
    }

    public func getBookState(id: String) async throws -> BookStateGetResponse {
        try await client.send(Endpoints.getBookState(bookId: id))
    }

    public func startBook(id: String) async throws -> BookStateResponse {
        try await client.send(Endpoints.startBook(bookId: id))
    }

    public func getEntitlements() async throws -> EntitlementResponse {
        try await client.send(Endpoints.getEntitlements())
    }
}
