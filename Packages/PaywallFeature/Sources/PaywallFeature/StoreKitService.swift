import Foundation
import StoreKit
import CoreKit
import Networking
import Models

// MARK: - Result types

/// The outcome of a `StoreKitService.purchase(_:)` call.
public enum PurchaseResult: Sendable, Equatable {
    /// The transaction was verified, the backend granted PRO, and the transaction was finished.
    case purchased
    /// The purchase is deferred (Ask-to-Buy awaiting parental approval, or SCA).
    case pending
    /// The user cancelled the purchase sheet.
    case userCancelled
}

/// Errors specific to `StoreKitService` that are not covered by `AppError`.
public enum StoreKitServiceError: Error, LocalizedError, Sendable {
    /// StoreKit returned an `.unverified` transaction — never grant access.
    case unverified(Error)
    /// No products were found for the configured product IDs.
    case noProductsFound

    public var errorDescription: String? {
        switch self {
        case .unverified:
            return "The purchase could not be verified. Please contact support."
        case .noProductsFound:
            return "Subscription products are unavailable right now. Please try again later."
        }
    }
}

// MARK: - Protocol

/// Abstraction over the concrete `StoreKitService` actor, allowing
/// `PaywallModel` and tests to swap in a mock.
public protocol StoreKitServicing: Sendable {
    /// Fires whenever the entitlement may have changed (purchase, renewal, refund, revocation).
    var entitlementChanges: AsyncStream<Void> { get }

    func loadProducts() async throws -> [Product]
    func purchase(_ product: Product) async throws -> PurchaseResult
    func restorePurchases() async throws
    func currentSubscriptionStatus() async throws -> SubscriptionStatus

    /// Re-verifies all currently-entitling Apple transactions with the backend,
    /// without calling `AppStore.sync()`. Used by `EntitlementService` reconciliation
    /// to process transactions the backend may have missed (e.g. after a renewal).
    /// Unlike `restorePurchases()`, this is safe to call on every foreground refresh.
    func verifyCurrentEntitlements() async throws
}

// MARK: - StoreKitService

/// Thread-safe StoreKit 2 service built as a Swift actor.
///
/// Responsibilities:
/// - Load products from App Store (`Product.products(for:)`).
/// - Drive the purchase flow (`product.purchase()`), handling all
///   `Product.PurchaseResult` cases.
/// - **Verify-then-finish:** POST the signed transaction JWS to the backend
///   via `POST /book/me/billing/apple/verify` and call `transaction.finish()`
///   **only after** the backend acknowledges success. An unverified StoreKit
///   transaction is rejected and never grants PRO.
/// - Maintain a long-lived `Transaction.updates` listener that processes
///   background renewals, refunds, and revocations through the same
///   verify-then-finish path.
/// - `restorePurchases()` via `AppStore.sync()` + re-reading current entitlements.
/// - Expose `currentSubscriptionStatus()` computed from
///   `Transaction.currentEntitlements` + `Product.SubscriptionInfo.Status`.
public actor StoreKitService: StoreKitServicing {

    // MARK: - Stored properties

    private let apiClient: any APIClientProtocol
    private let config: StoreKitConfig
    private let log = AppLog(category: .billing)

    /// Long-lived listener for `Transaction.updates`.
    /// `nonisolated(unsafe)` lets the init assign it after capturing `self` in a Task,
    /// and lets `deinit` cancel it without an actor hop.
    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?

    // MARK: - Entitlement change stream

    /// Fires `Void` whenever the entitlement may have changed.
    /// `nonisolated` so observers can iterate without `await`.
    public nonisolated let entitlementChanges: AsyncStream<Void>
    private let entitlementContinuation: AsyncStream<Void>.Continuation

    // MARK: - Init / deinit

    public init(apiClient: any APIClientProtocol, config: StoreKitConfig) {
        self.apiClient = apiClient
        self.config = config

        var continuation: AsyncStream<Void>.Continuation!
        self.entitlementChanges = AsyncStream<Void> { cont in continuation = cont }
        self.entitlementContinuation = continuation

        // listenerTask is nil (Optional default) at this point — self is fully initialized.
        // Start the background listener after self is complete.
        self.listenerTask = Task {
            await self.listenForTransactionUpdates()
        }
    }

    nonisolated deinit {
        listenerTask?.cancel()
        entitlementContinuation.finish()
    }

    // MARK: - Public API

    /// Fetches subscription products from the App Store for all configured product IDs.
    public func loadProducts() async throws -> [Product] {
        let ids = config.allProductIDs
        guard !ids.isEmpty else { throw StoreKitServiceError.noProductsFound }
        let products = try await Product.products(for: ids)
        guard !products.isEmpty else { throw StoreKitServiceError.noProductsFound }
        return products.sorted { lhs, rhs in
            lhs.id == config.annualProductID && rhs.id != config.annualProductID
        }
    }

    /// Initiates the purchase flow for `product`.
    ///
    /// - Returns: `.purchased` after backend verification and `transaction.finish()`.
    ///   Returns `.pending` for Ask-to-Buy / SCA deferral, `.userCancelled` when dismissed.
    /// - Throws: `StoreKitServiceError.unverified` if StoreKit cannot verify the transaction.
    ///   Throws `AppError` propagated from the backend verify call.
    ///   The transaction is NOT finished in either error path.
    public func purchase(_ product: Product) async throws -> PurchaseResult {
        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .unverified(_, let error):
                log.warning("Purchase returned unverified transaction — not granting PRO")
                throw StoreKitServiceError.unverified(error)
            case .verified:
                try await handleVerifiedResult(verificationResult)
                return .purchased
            }
        case .pending:
            log.info("Purchase is pending (Ask-to-Buy or SCA)")
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    /// Restores purchases by syncing with the App Store and re-verifying
    /// all current entitlement transactions with the backend.
    public func restorePurchases() async throws {
        try await AppStore.sync()
        try await verifyCurrentEntitlements()
    }

    /// Re-verifies all currently-entitling Apple transactions with the backend,
    /// **without** calling `AppStore.sync()`. Safe to call on every foreground refresh
    /// as part of cross-platform reconciliation.
    public func verifyCurrentEntitlements() async throws {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  config.allProductIDs.contains(transaction.productID) else { continue }
            do {
                try await handleVerifiedResult(result)
            } catch {
                log.warning("verifyCurrentEntitlements: failed for \(transaction.productID): \(error.localizedDescription)")
            }
        }
    }

    /// Computes the current subscription status from `Transaction.currentEntitlements`
    /// and `Product.SubscriptionInfo.Status`.
    public func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        var bestProductID: String?
        var bestExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard config.allProductIDs.contains(transaction.productID) else { continue }

            if let revoked = transaction.revocationDate, revoked <= Date() {
                return .revoked
            }
            bestProductID = transaction.productID
            bestExpirationDate = transaction.expirationDate
        }

        guard let productID = bestProductID else {
            return .notSubscribed
        }

        // Refine with subscription lifecycle state (grace period, billing retry).
        let products = (try? await Product.products(for: [productID])) ?? []
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard case .verified = status.renewalInfo,
                      case .verified = status.transaction else { continue }

                let state = status.state
                if state == .subscribed {
                    return .subscribed(productID: productID, expirationDate: bestExpirationDate)
                } else if state == .inGracePeriod {
                    return .inGracePeriod(productID: productID, expirationDate: bestExpirationDate)
                } else if state == .inBillingRetryPeriod {
                    return .inBillingRetry(productID: productID)
                } else if state == .revoked {
                    return .revoked
                } else if state == .expired {
                    return .expired(productID: productID)
                }
                // Unknown state — treat as subscribed to avoid incorrectly locking out a user.
                return .subscribed(productID: productID, expirationDate: bestExpirationDate)
            }
        }

        return .subscribed(productID: productID, expirationDate: bestExpirationDate)
    }

    // MARK: - Private

    private func listenForTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            switch verificationResult {
            case .unverified(_, let error):
                log.warning("Transaction.updates: unverified transaction ignored: \(error.localizedDescription)")
            case .verified:
                do {
                    try await handleVerifiedResult(verificationResult)
                } catch {
                    log.error("Transaction.updates: failed to handle transaction: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Core verify-then-finish routine.
    ///
    /// 1. Extracts the JWS from `VerificationResult.jwsRepresentation`.
    /// 2. POSTs the JWS to the backend (backend verifies against Apple certs and grants PRO).
    /// 3. Calls `transaction.finish()` only after the backend succeeds.
    /// 4. Signals `entitlementChanges` so observers refresh the UI.
    private func handleVerifiedResult(_ verificationResult: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = verificationResult else { return }

        let endpoint = try Endpoints.verifyApplePurchase(
            jwsRepresentation: verificationResult.jwsRepresentation
        )
        let _: EntitlementResponse = try await apiClient.send(endpoint)

        await transaction.finish()
        log.info("Transaction finished after backend grant: \(transaction.productID)")
        entitlementContinuation.yield(())
    }
}
