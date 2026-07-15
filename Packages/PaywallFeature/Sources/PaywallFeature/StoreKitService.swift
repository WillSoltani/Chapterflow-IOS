import Foundation
import StoreKit
import Synchronization
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
    /// The account-owned service has been quiesced or permanently stopped.
    case inactive

    public var errorDescription: String? {
        switch self {
        case .unverified:
            return "The purchase could not be verified. Please contact support."
        case .noProductsFound:
            return "Subscription products are unavailable right now. Please try again later."
        case .inactive:
            return "Purchases are unavailable for this session."
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

    /// Returns the UInt64 transaction ID of the currently-entitling Apple transaction,
    /// or `nil` when no verified subscription transaction exists.
    ///
    /// Used to populate the in-app refund-request sheet
    /// (`Transaction.beginRefundRequest(for:in:)` / SwiftUI `.refundRequestSheet`).
    func currentTransactionID() async -> UInt64?

    /// Returns the set of configured product IDs for which the current user is eligible
    /// to receive an introductory offer (free trial or discounted intro price).
    ///
    /// Only products in the returned set should display trial/intro pricing on the
    /// paywall. Users who have previously redeemed an introductory offer for ANY
    /// product in the subscription group are ineligible.
    func introOfferEligibleProductIDs() async -> Set<String>

    /// Returns display info for the best eligible win-back offer across all configured
    /// products, or `nil` when the user has no lapsed subscription or no win-back
    /// offers are configured in App Store Connect.
    ///
    /// The App Store sorts eligible offers with the best offer first.
    func winBackDisplayInfo() async -> WinBackDisplayInfo?

    /// Purchases a subscription using a win-back offer identified by `offerID`
    /// for the product identified by `productID`.
    ///
    /// The verify-then-finish path is identical to `purchase(_:)`.
    func purchaseWithWinBack(productID: String, offerID: String) async throws -> PurchaseResult

    /// Reversibly quiesces account-bound StoreKit work and awaits listener cancellation.
    func pause() async
    /// Restarts the transaction listener after a reversible pause.
    func resume() async
    /// Permanently stops this account-bound service and awaits listener cancellation.
    func stop() async
}

// MARK: - Default implementations

/// No-op defaults so existing preview / test stubs only need to override methods they care about.
public extension StoreKitServicing {
    func introOfferEligibleProductIDs() async -> Set<String> { [] }
    func winBackDisplayInfo() async -> WinBackDisplayInfo? { nil }
    func purchaseWithWinBack(productID: String, offerID: String) async throws -> PurchaseResult { .userCancelled }
    func pause() async {}
    func resume() async {}
    func stop() async {}
}

enum StoreKitServiceLifecycleState: Sendable, Equatable {
    case active
    case paused
    case stopped
}

struct StoreKitServiceLifecycleSnapshot: Sendable, Equatable {
    let state: StoreKitServiceLifecycleState
    let listenerStartCount: Int
    let hasListener: Bool
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

    typealias ListenerOperation = @Sendable () async -> Void

    // MARK: - Stored properties

    private let apiClient: any APIClientProtocol
    private let config: StoreKitConfig
    private let log = AppLog(category: .billing)

    /// Long-lived listener for `Transaction.updates`. The mutex is only a task-handle
    /// lifetime box: all lifecycle decisions remain actor-isolated, while deinit can
    /// still synchronously cancel the retained task without an unsafe isolation escape.
    private let listenerTask = Mutex<Task<Void, Never>?>(nil)
    private let listenerOperation: ListenerOperation?
    private var lifecycleState: StoreKitServiceLifecycleState
    private var lifecycleGeneration = 0
    private var listenerStartCount = 0

    // MARK: - Entitlement change stream

    /// Fires `Void` whenever the entitlement may have changed.
    /// `nonisolated` so observers can iterate without `await`.
    public nonisolated let entitlementChanges: AsyncStream<Void>
    private let entitlementContinuation: AsyncStream<Void>.Continuation

    // MARK: - Init / deinit

    public init(apiClient: any APIClientProtocol, config: StoreKitConfig) {
        self.apiClient = apiClient
        self.config = config
        self.listenerOperation = nil
        self.lifecycleState = .active

        var continuation: AsyncStream<Void>.Continuation!
        self.entitlementChanges = AsyncStream<Void> { cont in continuation = cont }
        self.entitlementContinuation = continuation

        listenerStartCount = 1
        listenerTask.withLock { task in
            task = Self.makeProductionListener(owner: self)
        }
    }

    init(
        apiClient: any APIClientProtocol,
        config: StoreKitConfig,
        listenerOperation: ListenerOperation?,
        automaticallyStarts: Bool
    ) {
        self.apiClient = apiClient
        self.config = config
        self.listenerOperation = listenerOperation
        self.lifecycleState = automaticallyStarts ? .active : .paused

        var continuation: AsyncStream<Void>.Continuation!
        self.entitlementChanges = AsyncStream<Void> { cont in continuation = cont }
        self.entitlementContinuation = continuation

        if automaticallyStarts {
            listenerStartCount = 1
            listenerTask.withLock { task in
                task = Self.makeListener(owner: self, operation: listenerOperation)
            }
        }
    }

    nonisolated deinit {
        listenerTask.withLock { task in
            task?.cancel()
            task = nil
        }
        entitlementContinuation.finish()
    }

    var lifecycleSnapshotForTesting: StoreKitServiceLifecycleSnapshot {
        StoreKitServiceLifecycleSnapshot(
            state: lifecycleState,
            listenerStartCount: listenerStartCount,
            hasListener: listenerTask.withLock { $0 != nil }
        )
    }

    // MARK: - Account lifetime

    public func pause() async {
        guard lifecycleState == .active else { return }
        lifecycleState = .paused
        lifecycleGeneration &+= 1
        await cancelListener()
    }

    public func resume() async {
        guard lifecycleState == .paused else { return }
        lifecycleState = .active
        lifecycleGeneration &+= 1
        startListener()
    }

    public func stop() async {
        guard lifecycleState != .stopped else { return }
        lifecycleState = .stopped
        lifecycleGeneration &+= 1
        await cancelListener()
        entitlementContinuation.finish()
    }

    // MARK: - Public API

    /// Fetches subscription products from the App Store for all configured product IDs.
    public func loadProducts() async throws -> [Product] {
        let generation = try activeGeneration()
        let ids = config.allProductIDs
        guard !ids.isEmpty else { throw StoreKitServiceError.noProductsFound }
        let products = try await Product.products(for: ids)
        try requireActive(generation: generation)
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
        let generation = try activeGeneration()
        let result = try await product.purchase()
        try requireActive(generation: generation)
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
        let generation = try activeGeneration()
        try await AppStore.sync()
        try requireActive(generation: generation)
        try await verifyCurrentEntitlements()
    }

    /// Re-verifies all currently-entitling Apple transactions with the backend,
    /// **without** calling `AppStore.sync()`. Safe to call on every foreground refresh
    /// as part of cross-platform reconciliation.
    public func verifyCurrentEntitlements() async throws {
        let generation = try activeGeneration()
        for await result in Transaction.currentEntitlements {
            try requireActive(generation: generation)
            guard case .verified(let transaction) = result,
                  config.allProductIDs.contains(transaction.productID) else { continue }
            do {
                try await handleVerifiedResult(result)
            } catch StoreKitServiceError.inactive {
                throw StoreKitServiceError.inactive
            } catch {
                log.warning("verifyCurrentEntitlements: failed for \(transaction.productID): \(error.localizedDescription)")
            }
        }
    }

    /// Computes the current subscription status from `Transaction.currentEntitlements`
    /// and `Product.SubscriptionInfo.Status`.
    public func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        let generation = try activeGeneration()
        var bestProductID: String?
        var bestExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            try requireActive(generation: generation)
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
        try requireActive(generation: generation)
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            try requireActive(generation: generation)
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

    /// Returns the UInt64 ID of the first currently-entitling verified transaction
    /// whose product ID matches the configured subscription product IDs.
    public func currentTransactionID() async -> UInt64? {
        guard lifecycleState == .active else { return nil }
        let generation = lifecycleGeneration
        for await result in Transaction.currentEntitlements {
            guard lifecycleState == .active,
                  lifecycleGeneration == generation else { return nil }
            guard case .verified(let transaction) = result,
                  config.allProductIDs.contains(transaction.productID) else { continue }
            return transaction.id
        }
        return nil
    }

    // MARK: - Offer eligibility

    /// Returns product IDs for which the current user is eligible for an introductory offer.
    ///
    /// Checks `Product.SubscriptionInfo.isEligibleForIntroOffer` per product.
    public func introOfferEligibleProductIDs() async -> Set<String> {
        guard lifecycleState == .active else { return [] }
        let generation = lifecycleGeneration
        let ids = config.allProductIDs
        guard !ids.isEmpty else { return [] }
        let products = (try? await Product.products(for: ids)) ?? []
        guard lifecycleState == .active,
              lifecycleGeneration == generation else { return [] }
        var eligible = Set<String>()
        for product in products {
            guard let subscription = product.subscription else { continue }
            if await subscription.isEligibleForIntroOffer {
                guard lifecycleState == .active,
                      lifecycleGeneration == generation else { return [] }
                eligible.insert(product.id)
            }
        }
        return eligible
    }

    /// Returns display info for the best eligible win-back offer.
    ///
    /// Checks `Product.SubscriptionInfo.RenewalInfo.eligibleWinBackOfferIDs`
    /// (sorted best-first by the App Store) against the configured win-back offers.
    public func winBackDisplayInfo() async -> WinBackDisplayInfo? {
        guard lifecycleState == .active else { return nil }
        let generation = lifecycleGeneration
        let ids = config.allProductIDs
        guard !ids.isEmpty else { return nil }
        let products = (try? await Product.products(for: ids)) ?? []
        guard lifecycleState == .active,
              lifecycleGeneration == generation else { return nil }

        for product in products {
            guard let subscription = product.subscription else { continue }
            let availableOffers = subscription.winBackOffers
            guard !availableOffers.isEmpty else { continue }

            // Pull subscription statuses to find which win-back offer IDs this user is eligible for.
            let statuses = (try? await product.subscription?.status) ?? []
            guard lifecycleState == .active,
                  lifecycleGeneration == generation else { return nil }
            var eligibleOfferIDs: [String] = []
            for status in statuses {
                if case .verified(let renewalInfo) = status.renewalInfo {
                    eligibleOfferIDs.append(contentsOf: renewalInfo.eligibleWinBackOfferIDs)
                }
            }

            // Match the first (best) eligible offer to its full offer object.
            guard let bestID = eligibleOfferIDs.first,
                  let offer = availableOffers.first(where: { $0.id == bestID })
            else { continue }

            return WinBackDisplayInfo(product: product, offer: offer)
        }
        return nil
    }

    /// Purchases a subscription using a win-back offer.
    ///
    /// Looks up the product and offer by ID, then calls `product.purchase(options:)`
    /// with `.winBackOffer(_:)`. The verify-then-finish path is identical to
    /// `purchase(_:)`, including posting the JWS to the backend.
    public func purchaseWithWinBack(productID: String, offerID: String) async throws -> PurchaseResult {
        let generation = try activeGeneration()
        let products = (try? await Product.products(for: [productID])) ?? []
        try requireActive(generation: generation)
        guard let product = products.first,
              let offer = product.subscription?.winBackOffers.first(where: { $0.id == offerID })
        else { throw StoreKitServiceError.noProductsFound }

        let result = try await product.purchase(options: [.winBackOffer(offer)])
        try requireActive(generation: generation)
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .unverified(_, let error):
                log.warning("Win-back purchase returned unverified transaction — not granting PRO")
                throw StoreKitServiceError.unverified(error)
            case .verified:
                try await handleVerifiedResult(verificationResult)
                return .purchased
            }
        case .pending:
            log.info("Win-back purchase is pending (Ask-to-Buy or SCA)")
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    // MARK: - Private

    private static func makeListener(
        owner: StoreKitService,
        operation: ListenerOperation?
    ) -> Task<Void, Never> {
        if let operation {
            return Task { await operation() }
        }
        return makeProductionListener(owner: owner)
    }

    private static func makeProductionListener(owner: StoreKitService) -> Task<Void, Never> {
        Task { [weak owner] in
            for await verificationResult in Transaction.updates {
                guard !Task.isCancelled, let owner else { return }
                await owner.processTransactionUpdate(verificationResult)
            }
        }
    }

    private func startListener() {
        guard lifecycleState == .active,
              listenerTask.withLock({ $0 == nil }) else { return }
        listenerStartCount += 1
        let task = Self.makeListener(owner: self, operation: listenerOperation)
        listenerTask.withLock { $0 = task }
    }

    private func cancelListener() async {
        let task = listenerTask.withLock { stored -> Task<Void, Never>? in
            defer { stored = nil }
            return stored
        }
        task?.cancel()
        await task?.value
    }

    private func processTransactionUpdate(
        _ verificationResult: VerificationResult<Transaction>
    ) async {
        guard lifecycleState == .active else { return }
        switch verificationResult {
        case .unverified:
            log.warning("Transaction.updates: unverified transaction ignored")
        case .verified:
            do {
                try await handleVerifiedResult(verificationResult)
            } catch StoreKitServiceError.inactive {
                // Account scope was quiesced while verification was in flight.
            } catch {
                log.error("Transaction.updates: transaction handling failed")
            }
        }
    }

    private func activeGeneration() throws -> Int {
        try requireActive()
        return lifecycleGeneration
    }

    private func requireActive(generation: Int? = nil) throws {
        guard lifecycleState == .active,
              generation.map({ $0 == lifecycleGeneration }) ?? true else {
            throw StoreKitServiceError.inactive
        }
    }

    /// Core verify-then-finish routine — handles direct purchases, renewals,
    /// offer-code redemptions, win-back purchases, and Family Sharing grants.
    ///
    /// Family Sharing: `Transaction.ownershipType == .familyShared` transactions arrive
    /// through `Transaction.updates` and `Transaction.currentEntitlements` the same as
    /// direct purchases. No special filtering by ownership type is applied here, so a
    /// family member's shared subscription is POSTed to the backend and grants Pro on
    /// their account automatically.
    ///
    /// 1. Extracts the JWS from `VerificationResult.jwsRepresentation`.
    /// 2. POSTs the JWS to the backend (backend verifies against Apple certs and grants PRO).
    /// 3. Calls `transaction.finish()` only after the backend succeeds.
    /// 4. Signals `entitlementChanges` so observers refresh the UI.
    private func handleVerifiedResult(_ verificationResult: VerificationResult<Transaction>) async throws {
        let generation = try activeGeneration()
        guard case .verified(let transaction) = verificationResult else { return }

        if transaction.ownershipType == .familyShared {
            log.info("Processing family-shared transaction for \(transaction.productID)")
        }

        let endpoint = try Endpoints.verifyApplePurchase(
            jwsRepresentation: verificationResult.jwsRepresentation
        )
        let _: EntitlementResponse = try await apiClient.send(endpoint)
        try requireActive(generation: generation)

        await transaction.finish()
        try requireActive(generation: generation)
        log.info("Transaction finished after backend grant: \(transaction.productID)")
        entitlementContinuation.yield(())
    }
}
