import Models
import CoreKit

/// Data-access protocol for fetching entitlement state from the server.
///
/// - ``LiveEntitlementRepository`` hits the real API.
/// - ``FakeEntitlementRepository`` returns canned data for tests and previews.
public protocol EntitlementRepository: Sendable {
    /// Fetches entitlement + paywall config.
    /// Maps to `GET /book/me/entitlements`.
    func getEntitlements() async throws -> EntitlementResponse

    /// Posts a signed Apple JWS transaction for server-side verification and PRO grant.
    /// Maps to `POST /book/me/billing/apple/verify`.
    func verifyAppleTransaction(_ jws: String) async throws -> ApplePurchaseVerificationResponse
}
