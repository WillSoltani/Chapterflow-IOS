import Foundation
import Models
import CoreKit
import Networking

/// Production ``EntitlementRepository`` backed by the ChapterFlow REST API.
public actor LiveEntitlementRepository: EntitlementRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func getEntitlements() async throws -> EntitlementResponse {
        try await client.send(Endpoints.getEntitlements())
    }

    public func verifyAppleTransaction(_ jws: String) async throws -> EntitlementResponse {
        let endpoint = try Endpoint(
            method: .post,
            path: "/book/me/billing/apple/verify",
            body: AppleVerifyBody(transactionJWS: jws)
        )
        return try await client.send(endpoint)
    }
}

// MARK: - Private

private struct AppleVerifyBody: Encodable, Sendable {
    let transactionJWS: String
}
