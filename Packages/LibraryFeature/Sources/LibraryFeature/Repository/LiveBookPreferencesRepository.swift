import Foundation
import Models
import Networking
import os

/// Production ``BookPreferencesRepository`` backed by ``APIClient``.
public actor LiveBookPreferencesRepository: BookPreferencesRepository {
    private let client: any APIClientProtocol
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "BookPreferencesRepository")

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func patchBookPreferredVariant(bookId: String, variantKey: String) async throws {
        let endpoint = try Endpoints.patchBookPreferredVariant(bookId: bookId, preferredVariant: variantKey)
        let _: BookStateResponse = try await client.send(endpoint)
    }
}
