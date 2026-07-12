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

    public func verifyAppleTransaction(
        _ jws: String
    ) async throws -> ApplePurchaseVerificationResponse {
        try await client.send(
            Endpoints.verifyApplePurchase(jwsRepresentation: jws)
        )
    }
}
