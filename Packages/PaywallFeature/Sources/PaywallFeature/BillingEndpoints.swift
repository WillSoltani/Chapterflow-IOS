import Networking
import Models

extension Endpoints {
    /// `POST /book/me/billing/apple/verify` — verifies a StoreKit 2 signed transaction JWS
    /// and grants the PRO entitlement server-side.
    ///
    /// - Parameter jwsRepresentation: `Transaction.jwsRepresentation` from StoreKit.
    ///   This is the Apple-signed compact serialisation of the transaction; the backend
    ///   verifies it against Apple's root certs and writes the entitlement.
    ///
    /// - Returns: An `Endpoint` that, when sent via `APIClient`, decodes the updated
    ///   `EntitlementResponse` from the server.
    public static func verifyApplePurchase(jwsRepresentation: String) throws -> Endpoint {
        struct Body: Encodable, Sendable {
            let transactionJWS: String
        }
        return try Endpoint(
            method: .post,
            path: "/book/me/billing/apple/verify",
            body: Body(transactionJWS: jwsRepresentation)
        )
    }
}
