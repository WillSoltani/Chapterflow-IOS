import CoreKit
import Foundation
import Models
import Networking
import Persistence
import Testing
@testable import PaywallFeature

@Suite("EntitlementService account and refresh isolation")
@MainActor
struct EntitlementServiceIsolationTests {
    @Test("account scope is stable and never contains the raw Cognito subject")
    func accountScopeIsOpaque() throws {
        let subject = "cognito-user-123@example.com"
        let first = try #require(EntitlementAccountScope(authenticatedSubject: subject))
        let second = try #require(EntitlementAccountScope(authenticatedSubject: subject))
        let other = try #require(EntitlementAccountScope(authenticatedSubject: "other-account"))

        #expect(first == second)
        #expect(first != other)
        #expect(!first.cacheKey.contains(subject))
        #expect(EntitlementAccountScope(authenticatedSubject: "  ") == nil)
    }

    @Test("legacy global cache is deleted and never migrated into an account")
    func legacyCacheIsDeleted() throws {
        let store = isolatedStore()
        try store.set(
            entitlement(plan: .pro, status: "active", unlockedBookIds: ["private-book"]),
            forKey: "com.chapterflow.entitlement.v1"
        )

        let service = EntitlementService(
            storeKitService: StubStoreKitService(),
            apiClient: MockAPIClient(),
            store: store
        )
        service.activateAccount(try scope("account-b"))

        #expect(!store.contains("com.chapterflow.entitlement.v1"))
        #expect(!service.isPro)
        #expect(!service.isBookUnlocked("private-book"))
    }

    @Test("deactivation erases account A before account B can load")
    func accountSwitchNeverInheritsPriorEntitlement() async throws {
        let store = isolatedStore()
        let client = MockAPIClient()
        try await client.setStub(
            response(
                entitlement(
                    plan: .pro,
                    status: "active",
                    unlockedBookIds: ["account-a-book"],
                    periodEnd: "2027-01-01T00:00:00Z",
                    cancelAtPeriodEnd: true
                )
            ),
            for: "/book/me/entitlements"
        )
        let service = EntitlementService(
            storeKitService: StubStoreKitService(),
            apiClient: client,
            store: store
        )
        let accountA = try scope("account-a")
        let accountB = try scope("account-b")

        service.activateAccount(accountA)
        await service.refresh()
        #expect(service.isPro)
        #expect(service.isBookUnlocked("account-a-book"))

        service.deactivateAccount()
        #expect(!service.isPro)
        #expect(!service.canStartNewBook)
        #expect(service.proSource == nil)
        #expect(service.remainingFreeStarts == 0)
        #expect(service.currentPeriodEnd == nil)
        #expect(service.cancelAtPeriodEnd == nil)
        #expect(!service.isBookUnlocked("account-a-book"))
        #expect(!store.contains(accountA.cacheKey))

        try await client.setStub(
            response(entitlement(plan: .free, remainingFreeStarts: 1)),
            for: "/book/me/entitlements"
        )
        service.activateAccount(accountB)
        #expect(!service.isPro)
        #expect(!service.isBookUnlocked("account-a-book"))
        await service.refresh()

        #expect(!service.isPro)
        #expect(service.remainingFreeStarts == 1)
        #expect(!service.isBookUnlocked("account-a-book"))
        #expect(store.contains(accountB.cacheKey))
    }

    @Test("late account A response cannot overwrite account B state or cache")
    func staleAccountResponseCannotCommit() async throws {
        let store = isolatedStore()
        let client = ControlledEntitlementClient()
        let service = EntitlementService(
            storeKitService: StubStoreKitService(),
            apiClient: client,
            store: store
        )
        let accountA = try scope("account-a")
        let accountB = try scope("account-b")

        service.activateAccount(accountA)
        let accountARefresh = Task { await service.refresh() }
        await client.waitForRequestCount(1)

        service.deactivateAccount()
        service.activateAccount(accountB)
        let accountBRefresh = Task { await service.refresh() }
        await client.waitForRequestCount(2)

        await client.succeedRequest(
            2,
            with: response(entitlement(plan: .free, remainingFreeStarts: 2))
        )
        await accountBRefresh.value
        await client.succeedRequest(
            1,
            with: response(
                entitlement(
                    plan: .pro,
                    status: "active",
                    unlockedBookIds: ["account-a-book"]
                )
            )
        )
        await accountARefresh.value

        let cachedAccountB: Entitlement? = store.value(forKey: accountB.cacheKey)
        #expect(!service.isPro)
        #expect(service.remainingFreeStarts == 2)
        #expect(!service.isBookUnlocked("account-a-book"))
        #expect(cachedAccountB?.plan == .free)
        #expect(!store.contains(accountA.cacheKey))
    }

    @Test("overlapping refreshes serialize and latest trailing response wins")
    func overlappingRefreshesRunOneTrailingFlight() async throws {
        let client = ControlledEntitlementClient()
        let service = EntitlementService(
            storeKitService: StubStoreKitService(),
            apiClient: client,
            store: isolatedStore()
        )
        service.activateAccount(try scope("single-flight-account"))

        let first = Task { await service.refresh() }
        await client.waitForRequestCount(1)
        let (secondStarted, secondStartedContinuation) = AsyncStream<Void>.makeStream()
        var secondStartedIterator = secondStarted.makeAsyncIterator()
        let second = Task { @MainActor in
            secondStartedContinuation.yield(())
            await service.refresh()
        }
        try #require(await secondStartedIterator.next() != nil)
        secondStartedContinuation.finish()

        #expect(await client.totalRequestCount() == 1)
        #expect(await client.maximumConcurrentRequestCount() == 1)

        await client.succeedRequest(
            1,
            with: response(entitlement(plan: .free, remainingFreeStarts: 1))
        )
        await client.waitForRequestCount(2)
        #expect(await client.maximumConcurrentRequestCount() == 1)
        await client.succeedRequest(
            2,
            with: response(entitlement(plan: .pro, status: "active"))
        )

        await first.value
        await second.value

        #expect(await client.totalRequestCount() == 2)
        #expect(await client.maximumConcurrentRequestCount() == 1)
        #expect(service.isPro)
    }

    @Test("backend-controlled server code collapses to the public server log code")
    func serverLogCodeIsRedacted() {
        let secret = "user@example.com-token-private_backend_code"
        let serverError = AppError.server(
            code: secret,
            message: secret,
            requestId: secret
        )

        let code = EntitlementService.safeErrorCode(serverError)
        #expect(code == "server")
        #expect(!code.contains(secret))
        #expect(EntitlementService.safeErrorCode(AppError.offline) == "offline")
        #expect(
            EntitlementService.safeErrorCode(SensitiveEntitlementTestError())
                == "entitlement_operation_failed"
        )
    }
}

private actor ControlledEntitlementClient: APIClientProtocol {
    private var nextRequestID = 1
    private var requests = 0
    private var activeRequests = 0
    private var maximumActiveRequests = 0
    private var pending: [
        Int: CheckedContinuation<EntitlementResponse, any Error>
    ] = [:]
    private var requestCountWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var fallback: EntitlementResponse?

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        guard endpoint.path == "/book/me/entitlements" else { throw AppError.notFound }
        let requestID = nextRequestID
        nextRequestID += 1
        requests += 1
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        defer { activeRequests -= 1 }
        resumeRequestCountWaiters()

        let response: EntitlementResponse
        if let fallback {
            response = fallback
        } else {
            response = try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = continuation
            }
        }
        guard let typedResponse = response as? T else {
            throw ControlledClientError.unexpectedResponseType
        }
        return typedResponse
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard requests < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func succeedRequest(_ requestID: Int, with response: EntitlementResponse) {
        pending.removeValue(forKey: requestID)?.resume(returning: response)
    }

    func releaseAll(with response: EntitlementResponse) {
        fallback = response
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(returning: response)
        }
    }

    func totalRequestCount() -> Int { requests }
    func maximumConcurrentRequestCount() -> Int { maximumActiveRequests }

    private func resumeRequestCountWaiters() {
        let satisfiedCounts = requestCountWaiters.keys.filter { $0 <= requests }
        for count in satisfiedCounts {
            let waiters = requestCountWaiters.removeValue(forKey: count) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

private enum ControlledClientError: Error, Sendable {
    case unexpectedResponseType
}

private struct SensitiveEntitlementTestError: Error, Sendable {}

private func isolatedStore() -> KeyValueStore {
    KeyValueStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
}

private func scope(_ subject: String) throws -> EntitlementAccountScope {
    try #require(EntitlementAccountScope(authenticatedSubject: subject))
}

private func response(_ entitlement: Entitlement) -> EntitlementResponse {
    EntitlementResponse(entitlement: entitlement, paywall: nil)
}

private func entitlement(
    plan: Entitlement.Plan,
    status: String? = nil,
    remainingFreeStarts: Int = 0,
    unlockedBookIds: [String] = [],
    periodEnd: String? = nil,
    cancelAtPeriodEnd: Bool? = nil
) -> Entitlement {
    Entitlement(
        plan: plan,
        proStatus: status,
        proSource: plan == .pro ? "apple" : nil,
        freeBookSlots: plan == .pro ? 0 : 2,
        unlockedBookIds: unlockedBookIds,
        unlockedBooksCount: unlockedBookIds.count,
        remainingFreeStarts: remainingFreeStarts,
        currentPeriodEnd: periodEnd,
        cancelAtPeriodEnd: cancelAtPeriodEnd,
        licenseKey: nil,
        licenseExpiresAt: nil
    )
}
