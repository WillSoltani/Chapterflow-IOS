import CoreKit
import Foundation
import Models
import Networking
import Testing
@testable import PaywallFeature

private let exactAccountID = "8f14e45f-ea4f-4a1b-8c32-07bbf1cdb22f"

private func accountBinding() throws -> StoreKitAccountBinding {
    try #require(StoreKitAccountBinding(accountID: exactAccountID))
}

private func storeKitConfig() -> StoreKitConfig {
    StoreKitConfig(monthlyProductID: "monthly", annualProductID: "annual")
}

private func activeEntitlementResponse() -> EntitlementResponse {
    EntitlementResponse(
        entitlement: Entitlement(
            plan: .pro,
            proStatus: "active",
            proSource: "apple",
            freeBookSlots: 0,
            unlockedBookIds: [],
            unlockedBooksCount: 0,
            remainingFreeStarts: 0,
            currentPeriodEnd: nil,
            cancelAtPeriodEnd: nil,
            licenseKey: nil,
            licenseExpiresAt: nil
        ),
        paywall: nil
    )
}

@Suite("StoreKit account authority")
struct StoreKitAccountAuthorityTests {
    @Test("exact UUID Cognito subject creates the identical StoreKit token")
    func exactUUIDCreatesBinding() throws {
        let binding = try accountBinding()
        #expect(binding.appAccountToken == UUID(uuidString: exactAccountID))
    }

    @Test(
        "invalid account identities fail closed",
        arguments: [
            "",
            "not-a-uuid",
            " \(exactAccountID)",
            "\(exactAccountID) ",
            "8f14e45fea4f4a1b8c3207bbf1cdb22f",
            "{\(exactAccountID)}",
        ]
    )
    func invalidIdentityHasNoBinding(_ accountID: String) {
        #expect(StoreKitAccountBinding(accountID: accountID) == nil)
    }

    @Test("description, debug description, and reflection redact the token")
    func bindingIsRedacted() throws {
        let binding = try accountBinding()
        let reflection = Mirror(reflecting: binding).children.map { child in
            "\(child.label ?? "")=\(child.value)"
        }.joined(separator: ",")

        #expect(binding.description == "StoreKitAccountBinding(<redacted>)")
        #expect(binding.debugDescription == "StoreKitAccountBinding(<redacted>)")
        #expect(!String(reflecting: binding).contains(exactAccountID))
        #expect(!reflection.contains(exactAccountID))
        #expect(reflection.contains("<redacted>"))
    }

    @Test("missing binding has a stable purchase-unavailable error")
    func missingBindingRejectsPurchaseOptions() async {
        let service = makeStoreKitService(binding: nil)

        do {
            _ = try await service.purchaseOptionIntents()
            Issue.record("A purchase plan was created without an account binding")
        } catch StoreKitServiceError.accountBindingUnavailable {
            #expect(
                StoreKitServiceError.accountBindingUnavailable.errorDescription
                    == "Purchases are unavailable for this account. Please sign in again."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await service.stop()
    }

    @Test("standard purchase plan contains only the exact account token")
    func standardPurchaseIsAccountBound() async throws {
        let binding = try accountBinding()
        let service = makeStoreKitService(binding: binding)

        let intents = try await service.purchaseOptionIntents()

        #expect(intents == [.appAccountToken(binding.appAccountToken)])
        await service.stop()
    }

    @Test("win-back plan retains its offer and exact account token")
    func winBackPurchaseIsAccountBound() async throws {
        let binding = try accountBinding()
        let service = makeStoreKitService(binding: binding)

        let intents = try await service.purchaseOptionIntents(winBackOfferID: "returning-reader")

        #expect(intents == [
            .appAccountToken(binding.appAccountToken),
            .winBackOffer("returning-reader"),
        ])
        await service.stop()
    }
}

@Suite("StoreKit authoritative transaction flights")
struct StoreKitTransactionFlightTests {
    @Test("concurrent same-transaction paths verify, finish, and signal once")
    func sameTransactionIsSingleFlight() async throws {
        let gate = ManualGate()
        let events = EventProbe()
        let verification = VerificationProbe(
            results: [.success(activeEntitlementResponse())],
            gate: gate,
            events: events
        )
        let finish = FinishProbe(events: events)
        let joined = AsyncSignal()
        let service = makeStoreKitService(verification: verification)

        let directPurchase = Task {
            try await service.processVerifiedTransaction(
                transactionID: 42,
                jwsRepresentation: "signed-fixture",
                finish: { await finish.run() }
            )
        }
        await verification.waitForCallCount(1)
        let listener = Task {
            try await service.processVerifiedTransaction(
                transactionID: 42,
                jwsRepresentation: "signed-fixture",
                onJoinedFlight: { await joined.signal() },
                finish: { await finish.run() }
            )
        }
        await joined.wait()

        #expect(await verification.callCount == 1)
        #expect(await service.verificationFlightCountForTesting == 1)
        await gate.open()
        try await directPurchase.value
        try await listener.value

        #expect(await verification.callCount == 1)
        #expect(await finish.count == 1)
        #expect(await service.entitlementChangeCountForTesting == 1)
        #expect(await service.verificationFlightCountForTesting == 0)
        #expect(await events.values == ["backend-success", "finish"])
        await service.stop()
    }

    @Test("backend failure leaves unfinished work retryable and unsignalled")
    func failureCanRetry() async throws {
        let verification = VerificationProbe(results: [
            .failure(.offline),
            .success(activeEntitlementResponse()),
        ])
        let finish = FinishProbe()
        let service = makeStoreKitService(verification: verification)

        await #expect(throws: AppError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 77,
                jwsRepresentation: "failed-fixture",
                finish: { await finish.run() }
            )
        }
        #expect(await finish.isEmpty)
        #expect(await service.entitlementChangeCountForTesting == 0)
        #expect(await service.verificationFlightCountForTesting == 0)

        try await service.processVerifiedTransaction(
            transactionID: 77,
            jwsRepresentation: "retry-fixture",
            finish: { await finish.run() }
        )

        #expect(await verification.callCount == 2)
        #expect(await finish.count == 1)
        #expect(await service.entitlementChangeCountForTesting == 1)
        await service.stop()
    }

    @Test("scope pause during backend verification prevents stale finish and signal")
    func pauseInvalidatesFlight() async {
        let gate = ManualGate()
        let verification = VerificationProbe(
            results: [.success(activeEntitlementResponse())],
            gate: gate
        )
        let finish = FinishProbe()
        let service = makeStoreKitService(verification: verification)
        let processing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 88,
                jwsRepresentation: "paused-fixture",
                finish: { await finish.run() }
            )
        }
        await verification.waitForCallCount(1)

        await service.pause()
        do {
            try await processing.value
            Issue.record("A paused verification flight completed successfully")
        } catch {
            // Expected: pause cancels the flight before finish or publication.
        }

        #expect(await finish.isEmpty)
        #expect(await service.entitlementChangeCountForTesting == 0)
        #expect(await service.verificationFlightCountForTesting == 0)
        #expect(await service.lifecycleSnapshotForTesting.state == .paused)
        await service.stop()
    }

    @Test("different transaction identities run independently")
    func differentTransactionsAreIndependent() async throws {
        let gate = ManualGate()
        let verification = VerificationProbe(
            results: [
                .success(activeEntitlementResponse()),
                .success(activeEntitlementResponse()),
            ],
            gate: gate
        )
        let finish = FinishProbe()
        let service = makeStoreKitService(verification: verification)
        let first = Task {
            try await service.processVerifiedTransaction(
                transactionID: 101,
                jwsRepresentation: "first-fixture",
                finish: { await finish.run() }
            )
        }
        await verification.waitForCallCount(1)
        let second = Task {
            try await service.processVerifiedTransaction(
                transactionID: 202,
                jwsRepresentation: "second-fixture",
                finish: { await finish.run() }
            )
        }
        await verification.waitForCallCount(2)

        #expect(await service.verificationFlightCountForTesting == 2)
        await gate.open()
        try await first.value
        try await second.value

        #expect(await verification.callCount == 2)
        #expect(await finish.count == 2)
        #expect(await service.entitlementChangeCountForTesting == 2)
        #expect(await service.verificationFlightCountForTesting == 0)
        await service.stop()
    }
}

private func makeStoreKitService(
    binding: StoreKitAccountBinding? = StoreKitAccountBinding(accountID: exactAccountID),
    verification: VerificationProbe? = nil
) -> StoreKitService {
    StoreKitService(
        apiClient: MockAPIClient(),
        config: storeKitConfig(),
        accountBinding: binding,
        verificationOperation: { jwsRepresentation in
            guard let verification else { return activeEntitlementResponse() }
            return try await verification.verify(jwsRepresentation)
        },
        listenerOperation: {},
        automaticallyStarts: true
    )
}

private actor ManualGate {
    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isOpen || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[waiterID] = continuation
                }
            }
            try Task.checkCancellation()
        } onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    func open() {
        isOpen = true
        let retainedWaiters = Array(waiters.values)
        waiters.removeAll()
        retainedWaiters.forEach { $0.resume() }
    }

    private func cancel(waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.resume()
    }
}

private actor AsyncSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignalled = true
        let retainedWaiters = waiters
        waiters.removeAll()
        retainedWaiters.forEach { $0.resume() }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor VerificationProbe {
    private struct CallWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var results: [Result<EntitlementResponse, AppError>]
    private let gate: ManualGate?
    private let events: EventProbe?
    private var calls: [String] = []
    private var callWaiters: [CallWaiter] = []

    init(
        results: [Result<EntitlementResponse, AppError>],
        gate: ManualGate? = nil,
        events: EventProbe? = nil
    ) {
        self.results = results
        self.gate = gate
        self.events = events
    }

    var callCount: Int { calls.count }

    func verify(_ jwsRepresentation: String) async throws -> EntitlementResponse {
        guard !results.isEmpty else { throw AppError.notFound }
        let result = results.removeFirst()
        calls.append(jwsRepresentation)
        resumeSatisfiedCallWaiters()
        if let gate {
            try await gate.wait()
        }
        let response = try result.get()
        await events?.record("backend-success")
        return response
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard calls.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(CallWaiter(
                expectedCount: expectedCount,
                continuation: continuation
            ))
        }
    }

    private func resumeSatisfiedCallWaiters() {
        var pending: [CallWaiter] = []
        for waiter in callWaiters {
            if calls.count >= waiter.expectedCount {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        callWaiters = pending
    }
}

private actor FinishProbe {
    private var finishes: [Bool] = []
    private let events: EventProbe?

    var count: Int { finishes.count }
    var isEmpty: Bool { finishes.isEmpty }

    init(events: EventProbe? = nil) {
        self.events = events
    }

    func run() async {
        finishes.append(true)
        await events?.record("finish")
    }
}

private actor EventProbe {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}
