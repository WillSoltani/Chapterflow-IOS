import CoreKit
import Foundation
import StoreKit

extension PaywallModel {
    static func safeBillingErrorMessage(for error: any Error) -> String {
        if storeKitNetworkError(from: error) != nil {
            return "We couldn't connect to the store. Check your connection and try again."
        }

        if let storeKitError = error as? StoreKitServiceError {
            return safeStoreKitBillingErrorMessage(for: storeKitError)
        }

        if let appError = error as? AppError {
            return safeAppBillingErrorMessage(for: appError)
        }

        if error is URLError {
            return "We couldn't connect to the store. Check your connection and try again."
        }
        return "The purchase couldn't be completed. Please try again."
    }

    static func storeKitNetworkError(from error: any Error) -> URLError? {
        guard let storeKitError = error as? StoreKitError,
              case .networkError(let networkError) = storeKitError else {
            return nil
        }
        return networkError
    }

    private static func safeStoreKitBillingErrorMessage(
        for error: StoreKitServiceError
    ) -> String {
        switch error {
        case .invalidConfiguration, .productNotConfigured:
            return "Subscriptions aren't available in this build. Please contact support."
        case .noProductsFound:
            return "Subscription options aren't available right now. Please try again later."
        case .unverified:
            return "The purchase couldn't be verified. Please contact support."
        case .accountBindingUnavailable:
            return "Please sign in again before managing purchases."
        case .accountBindingMismatch:
            return "This purchase belongs to another ChapterFlow account. Sign in to that account and try again."
        case .accountChangedDuringVerification:
            return "Your account changed while we confirmed the purchase. Check your membership and try again."
        case .unsupportedOwnership:
            return "This subscription can't be added to this account. Please contact support."
        case .transactionNotActive:
            return "This subscription is no longer active. Choose a plan to continue."
        case .processedWithoutActiveEntitlement:
            return "Your purchase was processed, but we couldn't confirm active access. Please contact support."
        }
    }

    private static func safeAppBillingErrorMessage(for error: AppError) -> String {
        switch error {
        case .unauthenticated, .reauthRequired:
            return "Please sign in again before managing purchases."
        case .offline:
            return "You're offline. Check your connection and try again."
        case .rateLimited:
            return "Please wait a moment before trying again."
        case .server(let code, _, _):
            return safeAppleVerificationMessage(for: code)
        case .verifierUnavailable, .forbidden, .invalidInput, .notFound, .decoding:
            return "We couldn't confirm the purchase. Please try again or contact support."
        }
    }

    nonisolated static func safeAppleVerificationMessage(for serverCode: String) -> String {
        switch serverCode {
        case "account_token_required", "account_token_malformed",
             "account_identifier_unsupported":
            return "Please sign in again before managing purchases."
        case "account_token_mismatch", "transaction_already_claimed":
            return "This purchase belongs to another ChapterFlow account. Sign in to that account and try again."
        case "family_shared_not_supported", "unsupported_ownership_type":
            return "This subscription can't be added to this account. Please contact support."
        case "bundle_mismatch", "transaction_environment_mismatch",
             "product_not_allowed", "subscription_group_mismatch",
             "unsupported_transaction_type", "unsupported_transaction",
             "invalid_transaction":
            return "We couldn't confirm the purchase. Please try again or contact support."
        default:
            return "We couldn't confirm the purchase. Please try again or contact support."
        }
    }
}
