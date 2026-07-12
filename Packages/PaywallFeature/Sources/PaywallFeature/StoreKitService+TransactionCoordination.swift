import Foundation
import StoreKit

extension StoreKitService {
    /// Testable transaction boundary shared by purchases, updates, and reconciliation.
    /// Returning `.ignored` means the transaction was outside the configured catalog
    /// and was intentionally ignored without a backend request, finish, or signal.
    @discardableResult
    func processVerifiedTransaction(
        transactionID: UInt64,
        productID: String,
        appAccountToken: UUID?,
        ownershipType: Transaction.OwnershipType = .purchased,
        jwsRepresentation: String,
        broadcastsTerminalRejection: Bool = true,
        broadcastsEntitlementChange: Bool = true,
        postCoordinatorTestHook: (@Sendable () async -> Void)? = nil,
        finish: @escaping @Sendable () async -> Void
    ) async throws -> StoreKitTransactionProcessingResult {
        guard config.allProductIDs.contains(productID) else {
            log.warning("Verified transaction ignored because the product is outside the configured catalog")
            return .ignored
        }

        let binding = try validatedAccountBinding(
            transactionAccountToken: appAccountToken,
            ownershipType: ownershipType
        )
        let key = StoreKitTransactionProcessingCoordinator.Key(
            transactionID: transactionID,
            accountToken: binding.token,
            accountSessionGeneration: binding.sessionGeneration
        )

        let coordinatorResult: Result<StoreKitTransactionProcessingResult, any Error>
        let participationID: UUID?
        do {
            let outcome = try await transactionProcessingCoordinator.perform(
                key: key
            ) { [self] in
                try await performVerifiedTransaction(
                    VerifiedTransactionExecution(
                        accountBinding: binding,
                        transactionID: transactionID,
                        isLegacyTokenless: appAccountToken == nil,
                        jwsRepresentation: jwsRepresentation
                    ),
                    finish: finish
                )
            }
            coordinatorResult = outcome.result
            participationID = outcome.participationID
        } catch {
            coordinatorResult = .failure(error)
            participationID = nil
        }
        await postCoordinatorTestHook?()
        guard accountContext.currentBinding() == binding else {
            await abandonParticipation(participationID, key: key)
            if case .failure(let error) = coordinatorResult {
                throw error
            }
            throw StoreKitServiceError.accountChangedDuringVerification
        }
        switch coordinatorResult {
        case .success(let processingResult):
            try await completeSuccessfulParticipation(
                participationID,
                key: key,
                binding: binding,
                requestsEvent: broadcastsEntitlementChange
            )
            return processingResult
        case .failure(let error):
            try await completeFailedParticipation(
                participationID,
                key: key,
                binding: binding,
                error: error,
                broadcastsTerminalRejection: broadcastsTerminalRejection
            )
        }
    }

    func transactionProcessingParticipantCount(for transactionID: UInt64) async -> Int {
        guard let activeAccountBinding = accountContext.currentBinding() else { return 0 }
        return await transactionProcessingCoordinator.participantCount(
            for: .init(
                transactionID: transactionID,
                accountToken: activeAccountBinding.token,
                accountSessionGeneration: activeAccountBinding.sessionGeneration
            )
        )
    }

    func entitlementChangePublicationCount() async -> UInt64 {
        await entitlementChangeBroadcaster.publishedEventCount()
    }

    private func validatedAccountBinding(
        transactionAccountToken: UUID?,
        ownershipType: Transaction.OwnershipType
    ) throws -> StoreKitAccountBinding {
        guard ownershipType == .purchased else {
            log.warning("Transaction rejected because its ownership type is unsupported")
            throw StoreKitServiceError.unsupportedOwnership
        }
        guard let activeAccountBinding = accountContext.currentBinding() else {
            log.warning("Transaction retained because no StoreKit account binding is active")
            throw StoreKitServiceError.accountBindingUnavailable
        }
        if let transactionAccountToken,
           transactionAccountToken != activeAccountBinding.token {
            log.warning("Transaction retained because its account binding does not match")
            throw StoreKitServiceError.accountBindingMismatch
        }
        return activeAccountBinding
    }

    private func abandonParticipation(
        _ participationID: UUID?,
        key: StoreKitTransactionProcessingCoordinator.Key
    ) async {
        guard let participationID else { return }
        _ = await transactionProcessingCoordinator.completeParticipation(
            key: key,
            participationID: participationID,
            requestsEvent: false
        )
    }

    private func completeSuccessfulParticipation(
        _ participationID: UUID?,
        key: StoreKitTransactionProcessingCoordinator.Key,
        binding: StoreKitAccountBinding,
        requestsEvent: Bool
    ) async throws {
        let publishesEvent = await completeParticipation(
            participationID,
            key: key,
            requestsEvent: requestsEvent
        )
        guard accountContext.currentBinding() == binding else {
            throw StoreKitServiceError.accountChangedDuringVerification
        }
        if publishesEvent {
            await entitlementChangeBroadcaster.publish(())
        }
    }

    private func completeFailedParticipation(
        _ participationID: UUID?,
        key: StoreKitTransactionProcessingCoordinator.Key,
        binding: StoreKitAccountBinding,
        error: any Error,
        broadcastsTerminalRejection: Bool
    ) async throws -> Never {
        let publishesEvent = await completeParticipation(
            participationID,
            key: key,
            requestsEvent: broadcastsTerminalRejection
                && Self.isTerminalTransactionRejection(error)
        )
        guard accountContext.currentBinding() == binding else {
            throw error
        }
        if publishesEvent {
            await entitlementChangeBroadcaster.publish(())
        }
        throw error
    }

    private func completeParticipation(
        _ participationID: UUID?,
        key: StoreKitTransactionProcessingCoordinator.Key,
        requestsEvent: Bool
    ) async -> Bool {
        guard let participationID else { return false }
        return await transactionProcessingCoordinator.completeParticipation(
            key: key,
            participationID: participationID,
            requestsEvent: requestsEvent
        )
    }
}
