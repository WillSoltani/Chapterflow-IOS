enum StoreKitTransactionVerification {
    /// Never trust fields from an unverified transaction to decide whether its
    /// failure is relevant. Every unverified current entitlement fails closed.
    static func currentEntitlementError(
        underlyingError: any Error
    ) -> StoreKitServiceError {
        .unverified(underlyingError)
    }
}
