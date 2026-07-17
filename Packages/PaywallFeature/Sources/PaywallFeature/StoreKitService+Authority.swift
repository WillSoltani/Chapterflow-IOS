import Foundation
import StoreKit

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

struct StoreKitTransactionFlight {
    let flightID: UUID
    let task: Task<Void, Error>
}

extension StoreKitService {
    /// Returns the complete account-bound intent set used by the production
    /// `Product.purchase(options:)` call. Package visibility keeps both purchase
    /// paths deterministic and testable without live StoreKit products.
    func purchaseOptionIntents(
        winBackOfferID: String? = nil
    ) throws -> Set<StoreKitPurchaseOptionIntent> {
        guard let accountBinding else {
            throw StoreKitServiceError.accountBindingUnavailable
        }
        var intents: Set<StoreKitPurchaseOptionIntent> = [
            .appAccountToken(accountBinding.appAccountToken),
        ]
        if let winBackOfferID {
            intents.insert(.winBackOffer(winBackOfferID))
        }
        return intents
    }

    func performPurchase(
        _ product: Product,
        optionIntents: Set<StoreKitPurchaseOptionIntent>
    ) async throws -> Product.PurchaseResult {
        var options: Set<Product.PurchaseOption> = []
        for intent in optionIntents {
            switch intent {
            case .appAccountToken(let token):
                options.insert(.appAccountToken(token))
            case .winBackOffer(let offerID):
                guard let offer = product.subscription?.winBackOffers.first(where: {
                    $0.id == offerID
                }) else {
                    throw StoreKitServiceError.noProductsFound
                }
                options.insert(.winBackOffer(offer))
            }
        }
        return try await product.purchase(options: options)
    }

    func cancelTransactionFlights() -> [Task<Void, Error>] {
        let retainedFlights = transactionFlights.values.map(\.task)
        transactionFlights.removeAll()
        retainedFlights.forEach { $0.cancel() }
        return retainedFlights
    }

    func awaitTransactionFlights(_ retainedFlights: [Task<Void, Error>]) async {
        for task in retainedFlights {
            _ = await task.result
        }
    }

    /// Testable transaction boundary shared by purchase, listener, restore, and
    /// reconciliation paths. One active transaction ID owns the backend call,
    /// finish, and entitlement signal; concurrent callers await that same task.
    func processVerifiedTransaction(
        transactionID: UInt64,
        jwsRepresentation: String,
        onJoinedFlight: (@Sendable () async -> Void)? = nil,
        finish: @escaping @Sendable () async -> Void
    ) async throws {
        if let existingFlight = transactionFlights[transactionID] {
            await onJoinedFlight?()
            return try await existingFlight.task.value
        }

        let generation = try activeGeneration()
        let flightID = UUID()
        let task = Task<Void, Error> { [weak self] in
            guard let self else { throw StoreKitServiceError.inactive }
            try await self.performTransactionFlight(
                jwsRepresentation: jwsRepresentation,
                generation: generation,
                finish: finish
            )
        }
        transactionFlights[transactionID] = StoreKitTransactionFlight(
            flightID: flightID,
            task: task
        )

        do {
            try await task.value
            removeTransactionFlight(transactionID: transactionID, flightID: flightID)
        } catch {
            removeTransactionFlight(transactionID: transactionID, flightID: flightID)
            throw error
        }
    }

    private func performTransactionFlight(
        jwsRepresentation: String,
        generation: Int,
        finish: @escaping @Sendable () async -> Void
    ) async throws {
        try Task.checkCancellation()
        try await verifyWithBackend(jwsRepresentation: jwsRepresentation)
        try Task.checkCancellation()
        try requireActive(generation: generation)

        await finish()
        try Task.checkCancellation()
        try requireActive(generation: generation)

        entitlementChangeCount += 1
        entitlementContinuation.yield(())
    }

    private func removeTransactionFlight(transactionID: UInt64, flightID: UUID) {
        guard transactionFlights[transactionID]?.flightID == flightID else { return }
        transactionFlights.removeValue(forKey: transactionID)
    }
}
