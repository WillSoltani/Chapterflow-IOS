import CoreKit
import Foundation
import Models
import Networking
import Persistence
import StoreKit
import Testing
@testable import PaywallFeature

private typealias FeatureSubscriptionStatus = PaywallFeature.SubscriptionStatus

private actor LifecycleStoreKitStub: StoreKitServicing {
    nonisolated let entitlementChanges: AsyncStream<Void>

    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    init() {
        entitlementChanges = AsyncStream { _ in }
    }

    func loadProducts() async throws -> [Product] { [] }
    func purchase(_ product: Product) async throws -> PurchaseResult { .userCancelled }
    func restorePurchases() async throws {}
    func currentSubscriptionStatus() async throws -> FeatureSubscriptionStatus { .notSubscribed }
    func verifyCurrentEntitlements() async throws {}
    func currentTransactionID() async -> UInt64? { nil }

    func pause() async { pauseCount += 1 }
    func resume() async { resumeCount += 1 }
    func stop() async { stopCount += 1 }
}

@Suite("Account-owned billing service lifetime")
struct AccountLifetimeServiceTests {
    @Test("StoreKit listener pause, resume, and final stop are idempotent")
    func storeKitListenerLifecycleIsDeterministic() async {
        let blocker = AsyncStream<Void>.makeStream()
        let service = StoreKitService(
            apiClient: MockAPIClient(),
            config: StoreKitConfig(monthlyProductID: "monthly", annualProductID: "annual"),
            listenerOperation: {
                for await _ in blocker.stream {}
            },
            automaticallyStarts: true
        )

        var snapshot = await service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .active)
        #expect(snapshot.listenerStartCount == 1)
        #expect(snapshot.hasListener)

        await service.pause()
        await service.pause()
        snapshot = await service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .paused)
        #expect(snapshot.listenerStartCount == 1)
        #expect(!snapshot.hasListener)

        await service.resume()
        await service.resume()
        snapshot = await service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .active)
        #expect(snapshot.listenerStartCount == 2)
        #expect(snapshot.hasListener)

        await service.stop()
        await service.stop()
        await service.resume()
        snapshot = await service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .stopped)
        #expect(snapshot.listenerStartCount == 2)
        #expect(!snapshot.hasListener)
        blocker.continuation.finish()
    }

    @Test("paused StoreKit service rejects new account work")
    func pausedStoreKitRejectsWork() async {
        let blocker = AsyncStream<Void>.makeStream()
        let service = StoreKitService(
            apiClient: MockAPIClient(),
            config: StoreKitConfig(monthlyProductID: "monthly", annualProductID: "annual"),
            listenerOperation: {
                for await _ in blocker.stream {}
            },
            automaticallyStarts: true
        )
        await service.pause()

        do {
            _ = try await service.loadProducts()
            Issue.record("Paused account service accepted new StoreKit work")
        } catch StoreKitServiceError.inactive {
            // Expected: the account scope is quiesced.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await service.stop()
        blocker.continuation.finish()
    }

    @Test("EntitlementService pause resumes the same state and final stop clears only memory")
    @MainActor
    func entitlementLifecycleIsReversibleThenFinal() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let store = KeyValueStore(defaults: defaults)
        let cached = Entitlement(
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
        )
        try store.set(cached, forKey: "com.chapterflow.entitlement.v1")
        let storeKit = LifecycleStoreKitStub()
        let service = EntitlementService(
            storeKitService: storeKit,
            apiClient: MockAPIClient(),
            store: store
        )
        #expect(service.isPro)

        service.start()
        service.start()
        var snapshot = service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .running)
        #expect(snapshot.storeKitListenerStartCount == 1)
        #expect(snapshot.refreshTaskStartCount == 1)

        await service.pause()
        await service.pause()
        snapshot = service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .paused)
        #expect(!snapshot.hasStoreKitListener)
        #expect(service.isPro)
        #expect(await storeKit.pauseCount == 1)

        await service.resume()
        await service.resume()
        snapshot = service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .running)
        #expect(snapshot.storeKitListenerStartCount == 2)
        #expect(snapshot.refreshTaskStartCount == 2)
        #expect(await storeKit.resumeCount == 1)

        await service.stop()
        await service.stop()
        await service.resume()
        snapshot = service.lifecycleSnapshotForTesting
        #expect(snapshot.state == .stopped)
        #expect(!snapshot.hasStoreKitListener)
        #expect(!service.isPro)
        #expect(!service.canStartNewBook)
        #expect(await storeKit.stopCount == 1)

        let restored = EntitlementService(
            storeKitService: LifecycleStoreKitStub(),
            apiClient: MockAPIClient(),
            store: store
        )
        #expect(restored.isPro, "Final teardown must retain account-bound durable cache data")
    }
}
