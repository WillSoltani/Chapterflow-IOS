import Networking

extension Endpoints {
    /// `POST /book/me/billing/apple/verify` — verifies a StoreKit 2 signed transaction JWS
    /// and grants the PRO entitlement server-side.
    ///
    /// - Parameter jwsRepresentation: `Transaction.jwsRepresentation` from StoreKit.
    ///   This is the Apple-signed compact serialisation of the transaction; the backend
    ///   verifies it against Apple's root certs and writes the entitlement.
    ///
    /// - Returns: An `Endpoint` whose success body is the backend's compact
    ///   verification acknowledgement and authoritative billing snapshot.
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
