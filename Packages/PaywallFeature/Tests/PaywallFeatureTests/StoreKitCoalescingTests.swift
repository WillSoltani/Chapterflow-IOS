import CoreKit
import Networking
import Testing
@testable import PaywallFeature

@Suite("StoreKit coalesced side effects")
struct StoreKitCoalescingTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test("a normal waiter still broadcasts when the coalesced leader is silent")
    func mixedSilentAndNormalParticipantsPreserveBroadcast() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let silentHistoryProcessing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 43,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                broadcastsTerminalRejection: false,
                broadcastsEntitlementChange: false,
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let normalUpdateProcessing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 43,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        var participantCount = 0
        for _ in 0..<1_000 {
            participantCount = await service.transactionProcessingParticipantCount(
                for: 43
            )
            if participantCount == 2 { break }
            await Task.yield()
        }
        try #require(participantCount == 2)

        await apiClient.releaseRequests()
        #expect(
            try await silentHistoryProcessing.value
                == .activeProcessed(proSource: "apple")
        )
        #expect(
            try await normalUpdateProcessing.value
                == .activeProcessed(proSource: "apple")
        )
        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await service.entitlementChangePublicationCount() == 1)
    }

    @Test("two normal participants publish exactly one entitlement event")
    func normalParticipantsPublishOneEvent() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let leader = Task {
            try await service.processVerifiedTransaction(
                transactionID: 47,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "coalesced-normal-participants-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let waiter = Task {
            try await service.processVerifiedTransaction(
                transactionID: 47,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "coalesced-normal-participants-jws",
                finish: { await finishRecorder.record() }
            )
        }

        var participantCount = 0
        for _ in 0..<1_000 {
            participantCount = await service.transactionProcessingParticipantCount(
                for: 47
            )
            if participantCount == 2 { break }
            await Task.yield()
        }
        try #require(participantCount == 2)

        await apiClient.releaseRequests()
        #expect(try await leader.value == .activeProcessed(proSource: "apple"))
        #expect(try await waiter.value == .activeProcessed(proSource: "apple"))
        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await service.entitlementChangePublicationCount() == 1)
    }

    @Test("coalesced waiter rejects an A to B account switch before broadcasting")
    func accountSwitchInvalidatesCoalescedWaiterLease() async throws {
        try await assertChangedLeaseRejectsCoalescedWaiter(
            transactionID: 44,
            returnsToFirstAccount: false
        )
    }

    @Test("coalesced waiter rejects an A to B to A session ABA before broadcasting")
    func accountABAInvalidatesCoalescedWaiterLease() async throws {
        try await assertChangedLeaseRejectsCoalescedWaiter(
            transactionID: 45,
            returnsToFirstAccount: true
        )
    }

    @Test(
        "stale coalesced terminal rejection suppresses its account broadcast",
        .timeLimit(.minutes(1))
    )
    func accountSwitchSuppressesTerminalRejectionBroadcast() async throws {
        let apiClient = GatedTerminalRejectionAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let waiterGate = PostCoordinatorWaiterGate()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let firstAccountToken = try activateStoreKitTestAccount(service)
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let leader = Task {
            try await service.processVerifiedTransaction(
                transactionID: 46,
                productID: "com.cf.monthly",
                appAccountToken: firstAccountToken,
                jwsRepresentation: "coalesced-terminal-rejection-jws",
                broadcastsTerminalRejection: false,
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let waiter = Task {
            try await service.processVerifiedTransaction(
                transactionID: 46,
                productID: "com.cf.monthly",
                appAccountToken: firstAccountToken,
                jwsRepresentation: "coalesced-terminal-rejection-jws",
                postCoordinatorTestHook: { await waiterGate.pause() },
                finish: { await finishRecorder.record() }
            )
        }

        var participantCount = 0
        for _ in 0..<1_000 {
            participantCount = await service.transactionProcessingParticipantCount(
                for: 46
            )
            if participantCount == 2 { break }
            await Task.yield()
        }
        try #require(participantCount == 2)

        var waiterPausedIterator = waiterGate.paused.makeAsyncIterator()
        await apiClient.releaseRequests()
        try #require(await waiterPausedIterator.next() != nil)
        await assertTerminalRejection(from: leader)

        #expect(service.activateAccount(
            authenticatedSubject: "00000000-0000-4000-8000-000000000222"
        ))
        await waiterGate.release()
        await assertTerminalRejection(from: waiter)

        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 0)
        #expect(await service.entitlementChangePublicationCount() == 0)
    }

    private func assertChangedLeaseRejectsCoalescedWaiter(
        transactionID: UInt64,
        returnsToFirstAccount: Bool
    ) async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let waiterGate = PostCoordinatorWaiterGate()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let firstAccountToken = try activateStoreKitTestAccount(service)
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let leader = Task {
            try await service.processVerifiedTransaction(
                transactionID: transactionID,
                productID: "com.cf.monthly",
                appAccountToken: firstAccountToken,
                jwsRepresentation: "coalesced-account-lease-jws",
                broadcastsEntitlementChange: false,
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let waiter = Task {
            try await service.processVerifiedTransaction(
                transactionID: transactionID,
                productID: "com.cf.monthly",
                appAccountToken: firstAccountToken,
                jwsRepresentation: "coalesced-account-lease-jws",
                postCoordinatorTestHook: { await waiterGate.pause() },
                finish: { await finishRecorder.record() }
            )
        }

        var participantCount = 0
        for _ in 0..<1_000 {
            participantCount = await service.transactionProcessingParticipantCount(
                for: transactionID
            )
            if participantCount == 2 { break }
            await Task.yield()
        }
        try #require(participantCount == 2)

        var waiterPausedIterator = waiterGate.paused.makeAsyncIterator()
        await apiClient.releaseRequests()
        try #require(await waiterPausedIterator.next() != nil)
        #expect(try await leader.value == .activeProcessed(proSource: "apple"))

        #expect(service.activateAccount(
            authenticatedSubject: "00000000-0000-4000-8000-000000000222"
        ))
        if returnsToFirstAccount {
            #expect(service.activateAccount(
                authenticatedSubject: storeKitTestAccountSubject
            ))
        }
        await waiterGate.release()

        do {
            let result = try await waiter.value
            Issue.record("Stale coalesced waiter returned \(result)")
        } catch let error as StoreKitServiceError {
            guard case .accountChangedDuringVerification = error else {
                Issue.record("Unexpected StoreKit error: \(error)")
                return
            }
        }

        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await service.entitlementChangePublicationCount() == 0)
    }

    private func assertTerminalRejection(
        from processing: Task<StoreKitTransactionProcessingResult, any Error>
    ) async {
        do {
            let result = try await processing.value
            Issue.record("Terminal rejection unexpectedly returned \(result)")
        } catch let AppError.server(code, _, _) {
            #expect(code == "transaction_revoked")
        } catch {
            Issue.record("Unexpected terminal rejection error: \(error)")
        }
    }
}

private actor PostCoordinatorWaiterGate {
    nonisolated let paused: AsyncStream<Void>

    private let pausedContinuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init() {
        (paused, pausedContinuation) = AsyncStream<Void>.makeStream()
    }

    func pause() async {
        pausedContinuation.yield(())
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor GatedTerminalRejectionAPIClient: APIClientProtocol {
    nonisolated let requestStarted: AsyncStream<Void>

    private let requestStartedContinuation: AsyncStream<Void>.Continuation
    private var pendingRequests: [CheckedContinuation<Void, Never>] = []
    private(set) var sendCount = 0

    init() {
        (requestStarted, requestStartedContinuation) = AsyncStream<Void>.makeStream()
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint
    ) async throws -> Response {
        sendCount += 1
        requestStartedContinuation.yield(())
        await withCheckedContinuation { continuation in
            pendingRequests.append(continuation)
        }
        throw AppError.server(
            code: "transaction_revoked",
            message: "The transaction is revoked.",
            requestId: "request-id"
        )
    }

    func releaseRequests() {
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests {
            request.resume()
        }
    }
}
