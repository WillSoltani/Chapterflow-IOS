import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Helpers

private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class StubClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private func makeFlowPointsClient(
    balance: Int = 1_000,
    ledger: [FlowLedgerEntry] = [],
    shopItems: [ShopItem] = []
) -> StubClient {
    let resp = FlowPointsResponse(balance: balance, ledger: ledger, equippedCosmetics: nil)
    let shop = ShopResponse(items: shopItems)
    return StubClient { endpoint in
        switch endpoint.path {
        case "/book/me/flow-points":
            return try JSONCoding.encoder.encode(resp)
        case "/book/me/shop":
            return try JSONCoding.encoder.encode(shop)
        default:
            throw AppError.notFound
        }
    }
}

private func makeRedeemClient(
    initialBalance: Int = 1_000,
    ledger: [FlowLedgerEntry] = [],
    shopItems: [ShopItem] = [],
    redeemResponse: RedeemFlowPointsResponse
) -> StubClient {
    StubClient { endpoint in
        switch endpoint.path {
        case "/book/me/flow-points":
            return try JSONCoding.encoder.encode(
                FlowPointsResponse(balance: initialBalance, ledger: ledger, equippedCosmetics: nil)
            )
        case "/book/me/shop":
            return try JSONCoding.encoder.encode(ShopResponse(items: shopItems))
        case "/book/me/flow-points/redeem":
            return try JSONCoding.encoder.encode(redeemResponse)
        default:
            throw AppError.notFound
        }
    }
}

// MARK: - Fixture helpers

private func makeLedgerEntry(id: String = "e1", amount: Int = 50) -> FlowLedgerEntry {
    FlowLedgerEntry(id: id, type: .earnDaily, amount: amount, description: "Daily", createdAt: "2026-07-01T08:00:00Z")
}

private func makeShopItem(
    id: String = "item-1",
    kind: ShopItemKind = .bonusBookUnlock,
    cost: Int = 250,
    isOwned: Bool? = false,
    isEquipped: Bool? = nil
) -> ShopItem {
    ShopItem(id: id, kind: kind, name: "Test Item", description: "Desc", cost: cost, isOwned: isOwned, isEquipped: isEquipped, previewColor: nil)
}

// MARK: - FlowPointsModel tests

@Suite("FlowPointsModel")
struct FlowPointsModelTests {

    @Test("initial state is .loading")
    @MainActor
    func initialStateIsLoading() {
        let repo = EngagementRepository(apiClient: makeFlowPointsClient(), modelContainer: nil)
        let model = FlowPointsModel(repository: repo)
        if case .loading = model.loadState {} else {
            Issue.record("Expected .loading initial state")
        }
    }

    @Test("load transitions to .loaded with balance and ledger")
    @MainActor
    func loadTransitionsToLoaded() async {
        let entry = makeLedgerEntry(amount: 100)
        let client = makeFlowPointsClient(balance: 750, ledger: [entry])
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }

        if case .loaded(let balance, let ledger) = model.loadState {
            #expect(balance == 750)
            #expect(ledger.count == 1)
            #expect(ledger[0].amount == 100)
        } else {
            Issue.record("Expected .loaded state after fetch")
        }
    }

    @Test("balance computed property returns 0 when not loaded")
    @MainActor
    func balanceDefaultsToZero() {
        let repo = EngagementRepository(apiClient: makeFlowPointsClient(), modelContainer: nil)
        let model = FlowPointsModel(repository: repo)
        #expect(model.balance == 0)
    }

    @Test("balance computed property reflects loaded state")
    @MainActor
    func balanceReflectsLoadedState() async {
        let client = makeFlowPointsClient(balance: 1_500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.balance == 1_500)
    }

    @Test("canAfford returns true when balance >= cost")
    @MainActor
    func canAffordSufficient() async {
        let item = makeShopItem(cost: 200)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.canAfford(item) == true)
    }

    @Test("canAfford returns false when balance < cost")
    @MainActor
    func canAffordInsufficient() async {
        let item = makeShopItem(cost: 1_000)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.canAfford(item) == false)
    }

    @Test("action for unowned affordable item is .buy")
    @MainActor
    func actionBuy() async {
        let item = makeShopItem(cost: 100, isOwned: false)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .buy)
    }

    @Test("action for unaffordable item is .buyDisabled")
    @MainActor
    func actionBuyDisabled() async {
        let item = makeShopItem(cost: 5_000, isOwned: false)
        let client = makeFlowPointsClient(balance: 100)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .buyDisabled)
    }

    @Test("action for owned non-cosmetic is .owned")
    @MainActor
    func actionOwned() async {
        let item = makeShopItem(kind: .bonusBookUnlock, isOwned: true)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .owned)
    }

    @Test("action for owned but not equipped cosmetic is .equip")
    @MainActor
    func actionEquip() async {
        let item = makeShopItem(kind: .theme, isOwned: true, isEquipped: false)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .equip)
    }

    @Test("action for currently equipped cosmetic is .equipped")
    @MainActor
    func actionEquipped() async {
        let item = makeShopItem(kind: .theme, isOwned: true, isEquipped: true)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .equipped)
    }

    @Test("action for .unknown kind is .hidden")
    @MainActor
    func actionHidden() async {
        let item = makeShopItem(kind: .unknown("holographic"), isOwned: false)
        let client = makeFlowPointsClient(balance: 500)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }
        #expect(model.action(for: item) == .hidden)
    }

    @Test("showConfirmation sets pendingItem; dismissConfirmation clears it")
    @MainActor
    func confirmationFlow() {
        let item = makeShopItem()
        let repo = EngagementRepository(apiClient: makeFlowPointsClient(), modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.showConfirmation(for: item)
        #expect(model.pendingItem?.id == item.id)

        model.dismissConfirmation()
        #expect(model.pendingItem == nil)
    }

    @Test("successful redeem updates balance immediately from response")
    @MainActor
    func redeemUpdatesBalance() async {
        let item = makeShopItem(cost: 250, isOwned: false)
        let redeemResp = RedeemFlowPointsResponse(balance: 750, item: nil, equippedCosmetics: nil)
        let client = makeRedeemClient(initialBalance: 1_000, redeemResponse: redeemResp)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }

        model.showConfirmation(for: item)
        model.confirm()
        // Wait for the redeem task to start, then run fully to completion
        // (redeem + two force-refreshes) — event-driven, no fixed deadline.
        await waitUntil(timeout: .seconds(2)) { model.isRedeeming }
        await waitUntil { !model.isRedeeming }

        // The model should reflect the refreshed balance (1_000 from the force-refresh)
        // rather than the transient intermediate state
        #expect(model.redeemError == nil)
        #expect(!model.isRedeeming)
    }

    @Test("failed redeem sets redeemError, isRedeeming returns to false")
    @MainActor
    func redeemFailureSetsError() async {
        let item = makeShopItem(cost: 250, isOwned: false)
        let client = StubClient { endpoint in
            switch endpoint.path {
            case "/book/me/flow-points":
                return try JSONCoding.encoder.encode(FlowPointsResponse(balance: 1_000))
            case "/book/me/shop":
                return try JSONCoding.encoder.encode(ShopResponse(items: []))
            case "/book/me/flow-points/redeem":
                throw AppError.server(code: "INSUFFICIENT_BALANCE", message: "Not enough points", requestId: nil)
            default:
                throw AppError.notFound
            }
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.load()
        await waitUntil { if case .loading = model.loadState { return false } else { return true } }

        model.showConfirmation(for: item)
        model.confirm()
        await waitUntil { model.redeemError != nil }

        #expect(model.redeemError != nil)
        #expect(!model.isRedeeming)
    }

    @Test("shopRewards filters to non-cosmetic items")
    @MainActor
    func shopRewardsFilter() async {
        let items = [
            makeShopItem(id: "r1", kind: .bonusBookUnlock),
            makeShopItem(id: "c1", kind: .theme),
            makeShopItem(id: "r2", kind: .proPass7d),
        ]
        let client = makeFlowPointsClient(shopItems: items)
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = FlowPointsModel(repository: repo)

        model.loadShopIfNeeded()
        await waitUntil { if case .loaded = model.shopLoadState { return true } else { return false } }

        #expect(model.shopRewards.map(\.id) == ["r1", "r2"])
        #expect(model.shopCosmetics.map(\.id) == ["c1"])
    }
}

// MARK: - Repository flow-points tests

@Suite("EngagementRepository — flow points")
struct RepositoryFlowPointsTests {

    @Test("fetchFlowPoints returns balance and ledger")
    func fetchFlowPoints() async throws {
        let entry = FlowLedgerEntry(id: "e1", type: .earnDaily, amount: 50, description: "Daily", createdAt: "2026-07-01T00:00:00Z")
        let client = makeFlowPointsClient(balance: 900, ledger: [entry])
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        let resp = try await repo.fetchFlowPoints()
        #expect(resp.balance == 900)
        #expect(resp.ledger?.count == 1)
        #expect(resp.ledger?.first?.type == .earnDaily)
    }

    @Test("fetchFlowPoints caches result within TTL")
    func fetchFlowPointsCaches() async throws {
        let callCount = Box(0)
        let client = StubClient { endpoint in
            if endpoint.path == "/book/me/flow-points" {
                callCount.value += 1
                return try JSONCoding.encoder.encode(FlowPointsResponse(balance: 500))
            }
            throw AppError.notFound
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchFlowPoints()
        _ = try await repo.fetchFlowPoints()
        #expect(callCount.value == 1, "Second call should hit the in-memory cache")
    }

    @Test("fetchShop returns items")
    func fetchShop() async throws {
        let item = makeShopItem(id: "s1", kind: .theme)
        let client = makeFlowPointsClient(shopItems: [item])
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        let resp = try await repo.fetchShop()
        #expect(resp.items.count == 1)
        #expect(resp.items[0].id == "s1")
    }

    @Test("redeemItem returns response and invalidates caches")
    func redeemItemInvalidatesCache() async throws {
        let flowCallCount = Box(0)
        let redeemResp = RedeemFlowPointsResponse(balance: 750, item: nil, equippedCosmetics: nil)
        let client = StubClient { endpoint in
            switch endpoint.path {
            case "/book/me/flow-points":
                flowCallCount.value += 1
                return try JSONCoding.encoder.encode(FlowPointsResponse(balance: 1_000))
            case "/book/me/shop":
                return try JSONCoding.encoder.encode(ShopResponse(items: []))
            case "/book/me/flow-points/redeem":
                return try JSONCoding.encoder.encode(redeemResp)
            default:
                throw AppError.notFound
            }
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        // Prime the cache
        _ = try await repo.fetchFlowPoints()
        #expect(flowCallCount.value == 1)

        // Redeem — should invalidate
        let resp = try await repo.redeemItem(itemId: "item-1", action: nil)
        #expect(resp.balance == 750)

        // Next fetch should hit network again (cache was invalidated)
        _ = try await repo.fetchFlowPoints()
        #expect(flowCallCount.value == 2, "Cache should be invalidated after redeem")
    }

    @Test("currentEquippedCosmetics is nil before first fetch")
    func equippedCosmeticsNilBeforeFetch() async {
        let repo = EngagementRepository(apiClient: makeFlowPointsClient(), modelContainer: nil)
        let cosmetics = await repo.currentEquippedCosmetics
        #expect(cosmetics == nil)
    }

    @Test("currentEquippedCosmetics reflects equipped state after fetch")
    func equippedCosmeticsAfterFetch() async throws {
        let equipped = EquippedCosmetics(themeId: "theme-1", frameId: nil)
        let client = StubClient { endpoint in
            guard endpoint.path == "/book/me/flow-points" else { throw AppError.notFound }
            return try JSONCoding.encoder.encode(
                FlowPointsResponse(balance: 500, ledger: nil, equippedCosmetics: equipped)
            )
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchFlowPoints()
        let cosmetics = await repo.currentEquippedCosmetics
        #expect(cosmetics?.themeId == "theme-1")
        #expect(cosmetics?.frameId == nil)
    }
}
