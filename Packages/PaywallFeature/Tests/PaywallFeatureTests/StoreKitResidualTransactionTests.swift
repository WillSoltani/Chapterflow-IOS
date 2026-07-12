import CoreKit
import Foundation
import Networking
import Testing
@testable import PaywallFeature

@Suite("StoreKit residual transaction safety")
struct StoreKitResidualTransactionTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test(
        "terminal verification rejection invalidates without finishing",
        arguments: ["transaction_revoked", "transaction_expired"]
    )
    func terminalVerificationRejectionInvalidates(
        serverCode: String
    ) async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let error = AppError.server(
            code: serverCode,
            message: "terminal transaction",
            requestId: "sensitive-request-id"
        )
        await apiClient.setStub(
            .failure(error),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        do {
            _ = try await service.processVerifiedTransaction(
                transactionID: 30,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
            Issue.record("Expected the terminal backend rejection")
        } catch let AppError.server(code, _, _) {
            #expect(code == serverCode)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await finishRecorder.finishCount == 0)
        #expect(await receivesEvent(in: stream))
        #expect(StoreKitService.safeErrorCode(error) == "server")
        #expect(StoreKitService.verificationEndpointHealth(after: error) == .healthy)
    }

    @Test("unfinished replay terminal rejection does not create an invalidation loop")
    func replayTerminalRejectionDoesNotBroadcast() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .failure(.server(
                code: "transaction_expired",
                message: "terminal transaction",
                requestId: nil
            )),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        await #expect(throws: AppError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 31,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                broadcastsTerminalRejection: false,
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await finishRecorder.finishCount == 0)
        #expect(!(await receivesEvent(in: stream)))
        #expect(await apiClient.recordedEndpoints.count == 1)
    }

    @Test(
        "cancelled duplicate exits while leader and another waiter complete once",
        .timeLimit(.minutes(1))
    )
    func cancelledDuplicateDoesNotWaitForLeader() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let entitlementStream = await service.entitlementChanges()
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let leader = Task {
            try await service.processVerifiedTransaction(
                transactionID: 43,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let (duplicateStarted, duplicateStartedContinuation) = AsyncStream<Void>.makeStream()
        var duplicateStartedIterator = duplicateStarted.makeAsyncIterator()
        let cancelledDuplicate = Task {
            duplicateStartedContinuation.yield(())
            return try await service.processVerifiedTransaction(
                transactionID: 43,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await duplicateStartedIterator.next() != nil)
        duplicateStartedContinuation.finish()
        #expect(await service.transactionProcessingParticipantCount(for: 43) == 2)

        cancelledDuplicate.cancel()
        await #expect(throws: CancellationError.self) {
            try await cancelledDuplicate.value
        }

        #expect(await service.transactionProcessingParticipantCount(for: 43) == 1)
        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 0)

        let (waiterStarted, waiterStartedContinuation) = AsyncStream<Void>.makeStream()
        var waiterStartedIterator = waiterStarted.makeAsyncIterator()
        let survivingDuplicate = Task {
            waiterStartedContinuation.yield(())
            return try await service.processVerifiedTransaction(
                transactionID: 43,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await waiterStartedIterator.next() != nil)
        waiterStartedContinuation.finish()
        #expect(await service.transactionProcessingParticipantCount(for: 43) == 2)

        await apiClient.releaseRequests()

        #expect(try await leader.value == .activeProcessed(proSource: "apple"))
        #expect(
            try await survivingDuplicate.value
                == .activeProcessed(proSource: "apple")
        )
        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: entitlementStream))
    }
}
