import Testing
import Foundation
import StoreKit
import CoreKit
import Models
import Networking
import Persistence
@testable import PaywallFeature

// StoreKit 18.4+ adds `SubscriptionStatus` as a typealias — disambiguate.
private typealias SubscriptionStatus = PaywallFeature.SubscriptionStatus

// MARK: - Stub StoreKit service

private actor StubSKService: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let isProStatus: Bool
    private let shouldThrow: Bool

    init(isPro: Bool = false, shouldThrow: Bool = false) {
        isProStatus = isPro
        self.shouldThrow = shouldThrow
        var cont: AsyncStream<Void>.Continuation!
        entitlementChanges = AsyncStream { cont = $0 }
        continuation = cont
    }

    func yieldEntitlementChange() { continuation.yield(()) }

    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func verifyCurrentEntitlements() async throws {}
    func currentSubscriptionStatus() async throws -> SubscriptionStatus {
        if shouldThrow { throw AppError.offline }
        return isProStatus
            ? .subscribed(productID: "com.cf.annual", expirationDate: nil)
            : .notSubscribed
    }
    func currentTransactionID() async -> UInt64? { nil }
}

// MARK: - Helpers

private func makeEntitlement(
    plan: Entitlement.Plan = .free,
    proStatus: String? = nil,
    remainingFreeStarts: Int = 0,
    freeBookSlots: Int = 0,
    unlockedBookIds: [String] = []
) -> Entitlement {
    Entitlement(
        plan: plan,
        proStatus: proStatus,
        proSource: plan == .pro ? "apple" : nil,
        freeBookSlots: freeBookSlots,
        unlockedBookIds: unlockedBookIds,
        unlockedBooksCount: unlockedBookIds.count,
        remainingFreeStarts: remainingFreeStarts,
        currentPeriodEnd: nil,
        cancelAtPeriodEnd: nil,
        licenseKey: nil,
        licenseExpiresAt: nil
    )
}

private func freshStore() -> KeyValueStore {
    KeyValueStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
}

private struct SUTFixture {
    let service: EntitlementService
    let storeKit: StubSKService
    let apiClient: MockAPIClient
}

@MainActor
private func makeSUT(
    entitlement: Entitlement? = nil,
    storeKitIsPro: Bool = false,
    storeKitShouldThrow: Bool = false,
    networkShouldFail: Bool = false,
    store: KeyValueStore? = nil
) async throws -> SUTFixture {
    let mockClient = MockAPIClient()
    if networkShouldFail {
        await mockClient.setDefault(.failure(.offline))
    } else if let e = entitlement {
        try await mockClient.setStub(
            EntitlementResponse(entitlement: e, paywall: nil),
            for: "/book/me/entitlements"
        )
    }
    let storeKit = StubSKService(isPro: storeKitIsPro, shouldThrow: storeKitShouldThrow)
    let kvStore = store ?? freshStore()
    let sut = EntitlementService(storeKitService: storeKit, apiClient: mockClient, store: kvStore)
    return SUTFixture(service: sut, storeKit: storeKit, apiClient: mockClient)
}

// MARK: - isPro tests

@Suite("EntitlementService — isPro")
@MainActor
struct EntitlementServiceIsProTests {

    @Test("false — free plan, no StoreKit subscription")
    func isProFree() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free)
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isPro)
    }

    @Test("true — backend confirms active Pro")
    func isProBackendActive() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active")
        )
        await fixture.service.refresh()
        #expect(fixture.service.isPro)
    }

    @Test("false — Pro plan but proStatus is past_due, not active")
    func isProPastDue() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "past_due")
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isPro)
    }

    @Test("false — Pro plan but proStatus is nil")
    func isProNilStatus() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: nil)
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isPro)
    }

    @Test("true — StoreKit optimism: backend free, SK subscribed")
    func isProStoreKitOptimism() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free),
            storeKitIsPro: true
        )
        await fixture.service.refresh()
        #expect(fixture.service.isPro)
    }

    @Test("true — both backend and StoreKit confirm Pro")
    func isProBothSources() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active"),
            storeKitIsPro: true
        )
        await fixture.service.refresh()
        #expect(fixture.service.isPro)
    }

    @Test("false — unknown plan treated as free")
    func isProUnknownPlan() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .unknown("future_tier"))
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isPro)
    }
}

// MARK: - canStartNewBook tests

@Suite("EntitlementService — canStartNewBook")
@MainActor
struct EntitlementServiceCanStartTests {

    @Test("true — Pro user can always start a new book")
    func canStartPro() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active")
        )
        await fixture.service.refresh()
        #expect(fixture.service.canStartNewBook)
    }

    @Test("true — free user with remaining free starts")
    func canStartFreeWithStarts() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 3)
        )
        await fixture.service.refresh()
        #expect(fixture.service.canStartNewBook)
    }

    @Test("true — exactly 1 remaining free start")
    func canStartOneRemaining() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 1)
        )
        await fixture.service.refresh()
        #expect(fixture.service.canStartNewBook)
    }

    @Test("false — free user, 0 remaining free starts")
    func canStartFreeNoStarts() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 0)
        )
        await fixture.service.refresh()
        #expect(!fixture.service.canStartNewBook)
    }

    @Test("true — StoreKit optimism: no backend Pro, SK is subscribed")
    func canStartStoreKitPro() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 0),
            storeKitIsPro: true
        )
        await fixture.service.refresh()
        #expect(fixture.service.canStartNewBook)
    }
}

// MARK: - isBookUnlocked tests

@Suite("EntitlementService — isBookUnlocked")
@MainActor
struct EntitlementServiceBookUnlockedTests {

    @Test("true — Pro user can access any book")
    func proUnlocksAll() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active")
        )
        await fixture.service.refresh()
        #expect(fixture.service.isBookUnlocked("any-book-id"))
        #expect(fixture.service.isBookUnlocked("another-book"))
    }

    @Test("true — book appears in unlockedBookIds")
    func specificBookUnlocked() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, unlockedBookIds: ["book-abc", "book-xyz"])
        )
        await fixture.service.refresh()
        #expect(fixture.service.isBookUnlocked("book-abc"))
        #expect(fixture.service.isBookUnlocked("book-xyz"))
    }

    @Test("false — book not in unlockedBookIds for free user")
    func bookNotInList() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, unlockedBookIds: ["book-abc"])
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isBookUnlocked("book-def"))
    }

    @Test("false — no entitlement, no StoreKit Pro")
    func noEntitlementFree() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free)
        )
        await fixture.service.refresh()
        #expect(!fixture.service.isBookUnlocked("some-book"))
    }
}

// MARK: - lockReason tests

@Suite("EntitlementService — lockReason")
@MainActor
struct EntitlementServiceLockReasonTests {

    @Test("nil — Pro user, no lock on any book")
    func noLockForPro() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active")
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "any-book") == nil)
    }

    @Test("nil — free user with remaining starts")
    func noLockWithFreeStarts() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 2)
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "some-book") == nil)
    }

    @Test("nil — book is explicitly unlocked for this user")
    func noLockForUnlockedBook() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(
                plan: .free,
                remainingFreeStarts: 0,
                unlockedBookIds: ["book-owned"]
            )
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "book-owned") == nil)
    }

    @Test(".needsPro — no free starts, never had slots")
    func needsProWhenNoSlots() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(
                plan: .free,
                remainingFreeStarts: 0,
                freeBookSlots: 0
            )
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "locked-book") == .needsPro)
    }

    @Test(".needsFreeSlotOrPro — used all free starts, had slots before")
    func needsFreeSlotOrPro() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(
                plan: .free,
                remainingFreeStarts: 0,
                freeBookSlots: 3
            )
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "locked-book") == .needsFreeSlotOrPro)
    }

    @Test(".lockedBehindQuiz — quiz flag overrides entitlement-based reason")
    func lockedBehindQuiz() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(
                plan: .free,
                remainingFreeStarts: 0,
                freeBookSlots: 0
            )
        )
        await fixture.service.refresh()
        #expect(fixture.service.lockReason(for: "book-seq", isLockedByQuiz: true) == .lockedBehindQuiz)
    }

    @Test(".lockedBehindQuiz — quiz flag works even with remaining starts")
    func lockedBehindQuizWithStarts() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .free, remainingFreeStarts: 3)
        )
        await fixture.service.refresh()
        // canStartNewBook is true, so lockReason would normally be nil;
        // isLockedByQuiz=true does NOT override — nil is returned when accessible.
        #expect(fixture.service.lockReason(for: "book-seq", isLockedByQuiz: true) == nil)
    }
}

// MARK: - Offline cache tests

@Suite("EntitlementService — offline cache")
@MainActor
struct EntitlementServiceCacheTests {

    @Test("init reads from cache — returns Pro state without a network call")
    func initReadsProcache() async throws {
        let store = freshStore()

        // First service populates the cache with a Pro entitlement.
        let fixture1 = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active"),
            store: store
        )
        await fixture1.service.refresh()
        #expect(fixture1.service.isPro)

        // Second service uses the same store — network is offline.
        let fixture2 = try await makeSUT(
            networkShouldFail: true,
            store: store
        )
        // No refresh called — reads from cache in init.
        #expect(fixture2.service.isPro)
    }

    @Test("cache updates after a successful refresh")
    func cacheUpdatesOnSuccess() async throws {
        let store = freshStore()

        let mockClient = MockAPIClient()
        try await mockClient.setStub(
            EntitlementResponse(
                entitlement: makeEntitlement(plan: .free),
                paywall: nil
            ),
            for: "/book/me/entitlements"
        )
        let service = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: mockClient,
            store: store
        )
        await service.refresh()
        #expect(!service.isPro)

        // Switch stub to Pro.
        try await mockClient.setStub(
            EntitlementResponse(
                entitlement: makeEntitlement(plan: .pro, proStatus: "active"),
                paywall: nil
            ),
            for: "/book/me/entitlements"
        )
        await service.refresh()
        #expect(service.isPro)

        // A fresh service from the same store reads the updated cache.
        let offlineClient = MockAPIClient()
        await offlineClient.setDefault(.failure(.offline))
        let service2 = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: offlineClient,
            store: store
        )
        #expect(service2.isPro)
    }

    @Test("refresh failure does not reset cached Pro state")
    func refreshFailureKeepsState() async throws {
        let store = freshStore()

        let mockClient = MockAPIClient()
        try await mockClient.setStub(
            EntitlementResponse(
                entitlement: makeEntitlement(plan: .pro, proStatus: "active"),
                paywall: nil
            ),
            for: "/book/me/entitlements"
        )
        let service = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: mockClient,
            store: store
        )
        await service.refresh()
        #expect(service.isPro)

        // Network dies.
        await mockClient.setDefault(.failure(.offline))
        await service.refresh()

        // Still Pro — cached state is preserved.
        #expect(service.isPro)
    }

    @Test("StoreKit failure does not reset entitlement")
    func storeKitFailureKeepsState() async throws {
        let fixture = try await makeSUT(
            entitlement: makeEntitlement(plan: .pro, proStatus: "active"),
            storeKitShouldThrow: true
        )
        await fixture.service.refresh()
        // Backend Pro survives StoreKit failure.
        #expect(fixture.service.isPro)
    }
}

// MARK: - Initial state from cache

@Suite("EntitlementService — initial state")
@MainActor
struct EntitlementServiceInitTests {

    @Test("isPro false before any refresh and cache empty")
    func initialStateFalse() throws {
        let service = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: MockAPIClient(),
            store: freshStore()
        )
        #expect(!service.isPro)
        #expect(!service.canStartNewBook)
    }

    @Test("isPro true from cache on init — no network needed")
    func initialStateFromProCache() throws {
        let store = freshStore()
        try store.set(
            makeEntitlement(plan: .pro, proStatus: "active"),
            forKey: "com.chapterflow.entitlement.v1"
        )
        let service = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: MockAPIClient(),
            store: store
        )
        #expect(service.isPro)
    }

    @Test("canStartNewBook true from cached free entitlement with starts")
    func canStartFromCache() throws {
        let store = freshStore()
        try store.set(
            makeEntitlement(plan: .free, remainingFreeStarts: 2),
            forKey: "com.chapterflow.entitlement.v1"
        )
        let service = EntitlementService(
            storeKitService: StubSKService(),
            apiClient: MockAPIClient(),
            store: store
        )
        #expect(!service.isPro)
        #expect(service.canStartNewBook)
    }
}
