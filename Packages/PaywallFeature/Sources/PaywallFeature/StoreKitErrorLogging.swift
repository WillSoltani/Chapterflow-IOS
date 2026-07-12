import CoreKit

extension StoreKitService {
    static func isTerminalTransactionRejection(_ error: any Error) -> Bool {
        if let storeKitError = error as? StoreKitServiceError,
           case .processedWithoutActiveEntitlement = storeKitError {
            return true
        }
        guard case .server(let code, _, _) = error as? AppError else {
            return false
        }
        return code == "transaction_revoked" || code == "transaction_expired"
    }

    static func verificationEndpointHealth(
        after error: any Error
    ) -> StoreKitVerificationEndpointHealth? {
        if error is CancellationError { return nil }
        guard let appError = error as? AppError else { return .unavailable }
        switch appError {
        case .unauthenticated, .reauthRequired:
            return nil
        case .rateLimited, .forbidden, .invalidInput:
            return .healthy
        case .server:
            return isTerminalTransactionRejection(appError) ? .healthy : .unavailable
        case .verifierUnavailable, .offline, .notFound, .decoding:
            return .unavailable
        }
    }

    /// Returns only allowlisted public log codes. In particular, server-supplied
    /// codes are untrusted and may contain account or transaction information.
    static func safeErrorCode(_ error: any Error) -> String {
        if let appError = error as? AppError {
            return safeAppErrorCode(appError)
        }
        if let storeKitError = error as? StoreKitServiceError {
            return safeStoreKitErrorCode(storeKitError)
        }
        return "storekit_operation_failed"
    }

    private static func safeAppErrorCode(_ error: AppError) -> String {
        switch error {
        case .unauthenticated:
            return "unauthenticated"
        case .reauthRequired:
            return "reauth_required"
        case .verifierUnavailable:
            return "verifier_unavailable"
        case .rateLimited:
            return "rate_limited"
        case .forbidden:
            return "forbidden"
        case .offline:
            return "offline"
        case .invalidInput:
            return "invalid_input"
        case .notFound:
            return "not_found"
        case .server:
            return "server"
        case .decoding:
            return "decoding"
        }
    }

    private static func safeStoreKitErrorCode(_ error: StoreKitServiceError) -> String {
        switch error {
        case .productNotConfigured:
            return "storekit_product_not_configured"
        case .accountBindingUnavailable:
            return "storekit_account_binding_unavailable"
        case .accountBindingMismatch:
            return "storekit_account_binding_mismatch"
        case .accountChangedDuringVerification:
            return "storekit_account_changed"
        case .unsupportedOwnership:
            return "storekit_ownership_unsupported"
        case .transactionNotActive:
            return "storekit_transaction_inactive"
        case .processedWithoutActiveEntitlement:
            return "storekit_entitlement_inactive"
        case .invalidConfiguration, .unverified, .noProductsFound:
            return "storekit_operation_failed"
        }
    }
}
