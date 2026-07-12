import CoreKit
import Foundation
import Networking
import StoreKit

struct VerifiedTransactionExecution: Sendable {
    let accountBinding: StoreKitAccountBinding
    let transactionID: UInt64
    let isLegacyTokenless: Bool
    let jwsRepresentation: String
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
/// - Maintain a long-lived `Transaction.updates` listener. Active renewals use
///   verify-then-finish; expired/revoked transactions finish only after the
///   backend explicitly acknowledges safe terminal processing.
/// - `restorePurchases()` via `AppStore.sync()` + re-reading current entitlements.
/// - Expose `currentSubscriptionStatus()` computed from
///   `Transaction.currentEntitlements` + `Product.SubscriptionInfo.Status`.
public actor StoreKitService: StoreKitServicing {

    // MARK: - Stored properties

    private let apiClient: any APIClientProtocol
    let config: StoreKitConfig
    private let diagnosticsRecorder: (any StoreKitDiagnosticsRecording)?
    let log = AppLog(category: .billing)
    let accountContext = StoreKitAccountContext()
    private var loadedProductIDs: Set<String> = []
    private var verificationEndpointHealth: StoreKitVerificationEndpointHealth = .notChecked

    let transactionProcessingCoordinator = StoreKitTransactionProcessingCoordinator()

    /// Long-lived listener for `Transaction.updates`.
    private let listenerTaskHandle = TaskCancellationHandle()

    // MARK: - Entitlement change broadcasts

    let entitlementChangeBroadcaster = AsyncEventBroadcaster<Void>()

    // MARK: - Init / deinit

    public init(
        apiClient: any APIClientProtocol,
        config: StoreKitConfig,
        diagnosticsRecorder: (any StoreKitDiagnosticsRecording)? = nil
    ) {
        self.apiClient = apiClient
        self.config = config
        self.diagnosticsRecorder = diagnosticsRecorder

        // listenerTask is nil (Optional default) at this point — self is fully initialized.
        // The task owns only a weak handler so an idle infinite sequence cannot retain
        // StoreKitService forever.
        listenerTaskHandle.replace(
            with: Self.liveTransactionListener { [weak self] verificationResult in
                await self?.handleTransactionUpdate(verificationResult)
            }
        )
    }

    init(
        apiClient: any APIClientProtocol,
        config: StoreKitConfig,
        diagnosticsRecorder: (any StoreKitDiagnosticsRecording)? = nil,
        listenerTaskFactory: StoreKitTransactionListenerTaskFactory
    ) {
        self.apiClient = apiClient
        self.config = config
        self.diagnosticsRecorder = diagnosticsRecorder
        listenerTaskHandle.replace(
            with: listenerTaskFactory { [weak self] verificationResult in
                await self?.handleTransactionUpdate(verificationResult)
            }
        )
    }

    nonisolated deinit {
        listenerTaskHandle.cancel()
    }

    // MARK: - Public API

    /// Returns a fresh stream for each observer. Events are broadcast to all
    /// active streams rather than divided between competing iterators.
    public func entitlementChanges() async -> AsyncStream<Void> {
        await entitlementChangeBroadcaster.stream()
    }

    /// Activates the StoreKit account scope for the signed-in Cognito subject.
    /// Invalid/non-UUID subjects fail closed and clear any previous binding.
    @discardableResult
    public nonisolated func activateAccount(authenticatedSubject: String) -> Bool {
        accountContext.activate(authenticatedSubject: authenticatedSubject)
    }

    /// Clears the StoreKit account scope immediately on sign-out/account teardown.
    public nonisolated func deactivateAccount() {
        accountContext.deactivate()
    }

    /// Fetches subscription products from the App Store for all configured product IDs.
    public func loadProducts() async throws -> [Product] {
        guard config.isValid else {
            loadedProductIDs = []
            await recordDiagnostics()
            throw StoreKitServiceError.invalidConfiguration
        }
        let ids = config.allProductIDs
        let products: [Product]
        do {
            products = try await Product.products(for: ids)
        } catch {
            loadedProductIDs = []
            await recordDiagnostics()
            throw error
        }
        let catalogProducts = products.filter { ids.contains($0.id) }
        loadedProductIDs = Set(catalogProducts.map(\.id))
        await recordDiagnostics()
        guard !catalogProducts.isEmpty else { throw StoreKitServiceError.noProductsFound }
        return catalogProducts.sorted { lhs, rhs in
            lhs.id == config.annualProductID && rhs.id != config.annualProductID
        }
    }

    /// Re-publishes the latest redacted snapshot after distribution access is
    /// resolved (for example, once a TestFlight app transaction is verified).
    public func publishDiagnostics() async {
        await recordDiagnostics()
    }

    /// Initiates the purchase flow for `product`.
    ///
    /// - Returns: `.purchased(proSource:)` after backend verification and
    ///   `transaction.finish()`. The source is the backend's authoritative
    ///   entitlement source, which need not be Apple.
    ///   Returns `.pending` for Ask-to-Buy / SCA deferral, `.userCancelled` when dismissed.
    /// - Throws: `StoreKitServiceError.unverified` if StoreKit cannot verify the transaction.
    ///   Throws `AppError` when the backend does not acknowledge processing; those
    ///   paths remain unfinished. A processed acknowledgement is safe to finish,
    ///   but the method still throws if no active authoritative Pro entitlement
    ///   remains or if the ChapterFlow account changed before UI completion.
    public func purchase(_ product: Product) async throws -> PurchaseResult {
        guard config.allProductIDs.contains(product.id) else {
            log.warning("Purchase rejected because the product is outside the configured catalog")
            throw StoreKitServiceError.productNotConfigured
        }
        let result = try await product.purchase(options: accountBoundPurchaseOptions())
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .unverified(_, let error):
                log.warning("Purchase returned unverified transaction — not granting PRO")
                throw StoreKitServiceError.unverified(error)
            case .verified:
                return try await purchaseResult(for: handleVerifiedResult(verificationResult))
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
        try await verifyUnfinishedTransactions()
        try await verifyCurrentEntitlements()
    }

    /// Replays every unfinished StoreKit transaction through the same
    /// catalog, ownership, account-token, backend, and finish gates used by a
    /// direct purchase. One bad transaction cannot prevent later items from
    /// being examined, but the first failure is reported after the pass.
    public func verifyUnfinishedTransactions() async throws {
        var firstFailure: (any Error)?
        for await result in Transaction.unfinished {
            switch result {
            case .unverified(_, let error):
                if firstFailure == nil {
                    firstFailure = StoreKitServiceError.unverified(error)
                }
            case .verified:
                do {
                    _ = try await handleVerifiedResult(
                        result,
                        broadcastsTerminalRejection: false
                    )
                } catch {
                    log.warning("Unfinished transaction replay failed: \(Self.safeErrorCode(error))")
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    /// Re-verifies all currently-entitling Apple transactions with the backend,
    /// **without** calling `AppStore.sync()`. Safe to call on every foreground refresh
    /// as part of cross-platform reconciliation.
    public func verifyCurrentEntitlements() async throws {
        var firstFailure: (any Error)?
        for await result in Transaction.currentEntitlements {
            switch result {
            case .unverified(_, let error):
                let verificationError = StoreKitTransactionVerification.currentEntitlementError(
                    underlyingError: error
                )
                log.warning("A current entitlement was unverified")
                if firstFailure == nil {
                    firstFailure = verificationError
                }
            case .verified(let transaction):
                guard config.allProductIDs.contains(transaction.productID) else { continue }
                do {
                    try await handleVerifiedResult(result)
                } catch {
                    log.warning("Current entitlement verification failed: \(Self.safeErrorCode(error))")
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    /// Computes the current subscription status from `Transaction.currentEntitlements`
    /// and `Product.SubscriptionInfo.Status`.
    public func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        let products = (try? await Product.products(for: config.allProductIDs)) ?? []
        await authorizeTokenlessSubscriptionHistory(in: products)

        var bestProductID: String?
        var bestExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard config.allProductIDs.contains(transaction.productID) else { continue }
            guard accountContext.ownsTransaction(
                id: transaction.id,
                appAccountToken: transaction.appAccountToken
            ) else { continue }

            if let revoked = transaction.revocationDate, revoked <= Date() {
                return .revoked
            }
            bestProductID = transaction.productID
            bestExpirationDate = transaction.expirationDate
        }

        if let lifecycleStatus = await accountOwnedLifecycleStatus(in: products) {
            return lifecycleStatus
        }
        guard let bestProductID else { return .notSubscribed }
        return .subscribed(productID: bestProductID, expirationDate: bestExpirationDate)
    }

    private func accountOwnedLifecycleStatus(
        in products: [Product]
    ) async -> SubscriptionStatus? {
        var terminalStatus: SubscriptionStatus?
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard case .verified = status.renewalInfo,
                      case .verified(let statusTransaction) = status.transaction,
                      accountContext.ownsTransaction(
                        id: statusTransaction.id,
                        appAccountToken: statusTransaction.appAccountToken
                      ) else { continue }

                let state = status.state
                if state == .subscribed {
                    return .subscribed(
                        productID: statusTransaction.productID,
                        expirationDate: statusTransaction.expirationDate
                    )
                } else if state == .inGracePeriod {
                    return .inGracePeriod(
                        productID: statusTransaction.productID,
                        expirationDate: statusTransaction.expirationDate
                    )
                } else if state == .inBillingRetryPeriod {
                    return .inBillingRetry(productID: statusTransaction.productID)
                } else if state == .revoked {
                    terminalStatus = .revoked
                } else if state == .expired {
                    if terminalStatus == nil {
                        terminalStatus = .expired(productID: statusTransaction.productID)
                    }
                } else {
                    // Unknown state: avoid presenting another purchase until
                    // the backend and StoreKit can resolve the lifecycle.
                    return .subscribed(
                        productID: statusTransaction.productID,
                        expirationDate: statusTransaction.expirationDate
                    )
                }
            }
        }
        return terminalStatus
    }

    /// Returns the UInt64 ID of the first currently-entitling verified transaction
    /// whose product ID matches the configured subscription product IDs.
    public func currentTransactionID() async -> UInt64? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  config.allProductIDs.contains(transaction.productID),
                  accountContext.ownsTransaction(
                    id: transaction.id,
                    appAccountToken: transaction.appAccountToken
                  ) else { continue }
            return transaction.id
        }
        return nil
    }

    // MARK: - Private

    private static func liveTransactionListener(
        _ handler: @escaping @Sendable (VerificationResult<Transaction>) async -> Void
    ) -> Task<Void, Never> {
        Task {
            for await verificationResult in Transaction.updates {
                guard !Task.isCancelled else { return }
                await handler(verificationResult)
            }
        }
    }

    private func handleTransactionUpdate(
        _ verificationResult: VerificationResult<Transaction>
    ) async {
        switch verificationResult {
        case .unverified:
            log.warning("Transaction update was unverified and ignored")
        case .verified:
            do {
                _ = try await handleVerifiedResult(verificationResult)
            } catch {
                log.error("Transaction update failed: \(Self.safeErrorCode(error))")
            }
        }
    }

    /// Returns the mandatory account-bound option used by every app-initiated
    /// purchase path. Package visibility keeps the invariant directly testable.
    func accountBoundPurchaseOptions() throws -> Set<Product.PurchaseOption> {
        guard let activeAccountBinding = accountContext.currentBinding() else {
            throw StoreKitServiceError.accountBindingUnavailable
        }
        return [activeAccountBinding.purchaseOption]
    }

    func purchaseResult(
        for processingResult: StoreKitTransactionProcessingResult
    ) throws -> PurchaseResult {
        switch processingResult {
        case .activeProcessed(let proSource):
            return .purchased(proSource: proSource)
        case .terminal:
            throw StoreKitServiceError.transactionNotActive
        case .ignored:
            throw StoreKitServiceError.productNotConfigured
        }
    }

    /// Core transaction routine for direct purchases, renewals, offer-code
    /// redemptions, and win-back purchases.
    ///
    /// 1. Rejects transactions outside the build's configured product catalog.
    /// 2. Requires a UUID-backed active account and rejects cross-account tokens.
    /// 3. Extracts the JWS from `VerificationResult.jwsRepresentation`.
    /// 4. POSTs the JWS to the backend for Apple and account-binding verification.
    /// 5. Finishes only after an authoritative active or terminal acknowledgement.
    @discardableResult
    func handleVerifiedResult(
        _ verificationResult: VerificationResult<Transaction>,
        broadcastsTerminalRejection: Bool = true,
        broadcastsEntitlementChange: Bool = true
    ) async throws -> StoreKitTransactionProcessingResult {
        guard case .verified(let transaction) = verificationResult else { return .ignored }

        return try await processVerifiedTransaction(
            transactionID: transaction.id,
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            ownershipType: transaction.ownershipType,
            jwsRepresentation: verificationResult.jwsRepresentation,
            broadcastsTerminalRejection: broadcastsTerminalRejection,
            broadcastsEntitlementChange: broadcastsEntitlementChange,
            finish: { await transaction.finish() }
        )
    }

    func performVerifiedTransaction(
        _ execution: VerifiedTransactionExecution,
        finish: @Sendable () async -> Void
    ) async throws -> StoreKitTransactionProcessingResult {
        let endpoint = try Endpoints.verifyApplePurchase(
            jwsRepresentation: execution.jwsRepresentation
        )
        let processingResult: StoreKitTransactionProcessingResult
        let processedWithoutActiveEntitlement: Bool
        do {
            let response: ApplePurchaseVerificationResponse = try await apiClient.send(endpoint)
            guard response.confirmsAuthoritativelyProcessed else {
                throw AppError.decoding(InvalidAppleVerificationAcknowledgement())
            }
            switch response.processedTransactionState {
            case .active:
                processedWithoutActiveEntitlement = !response.authoritativeProIsActive
                processingResult = .activeProcessed(proSource: response.entitlement.proSource)
            case .expired, .revoked:
                processedWithoutActiveEntitlement = false
                processingResult = .terminal
            case .unknown, nil:
                // `confirmsAuthoritativelyProcessed` already excludes this,
                // but keep the finish gate locally explicit and fail closed.
                throw AppError.decoding(InvalidAppleVerificationAcknowledgement())
            }
            if execution.isLegacyTokenless {
                accountContext.authorizeLegacyTransaction(
                    execution.transactionID,
                    for: execution.accountBinding
                )
            }
            verificationEndpointHealth = .healthy
            await recordDiagnostics()
        } catch {
            if let health = Self.verificationEndpointHealth(after: error) {
                verificationEndpointHealth = health
                await recordDiagnostics()
            }
            throw error
        }

        await finish()
        log.info("Transaction finished after authoritative backend processing")
        guard accountContext.currentBinding() == execution.accountBinding else {
            throw StoreKitServiceError.accountChangedDuringVerification
        }
        if processedWithoutActiveEntitlement {
            throw StoreKitServiceError.processedWithoutActiveEntitlement
        }
        return processingResult
    }

    private func recordDiagnostics() async {
        guard let diagnosticsRecorder else { return }
        _ = await diagnosticsRecorder.recordStoreKitDiagnostics(
            StoreKitDiagnosticsRecord(
                configuredProductIDs: config.allProductIDs.sorted(),
                loadedProductIDs: loadedProductIDs.sorted(),
                verificationEndpointHealth: verificationEndpointHealth
            )
        )
    }

}
