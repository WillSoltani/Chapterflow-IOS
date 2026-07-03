import Observation
import CoreKit
import Models

// MARK: - FlowPointsModel

/// View model for the Flow-Points economy screen.
///
/// Manages: balance display, transaction ledger, shop catalogue,
/// confirmation flow before redeem/equip, and error presentation.
/// All state mutations are server-authoritative — the model reflects
/// the server response, never grants locally.
@Observable
@MainActor
public final class FlowPointsModel {

    // MARK: - Nested types

    public enum Tab: Hashable {
        case ledger
        case shop
    }

    public enum LoadState {
        case loading
        case loaded(balance: Int, ledger: [FlowLedgerEntry])
        case error(AppError)
    }

    public enum ShopLoadState {
        case idle
        case loading
        case loaded([ShopItem])
        case error(AppError)
    }

    // MARK: - State

    public private(set) var loadState: LoadState = .loading
    public private(set) var shopLoadState: ShopLoadState = .idle
    public var selectedTab: Tab = .ledger
    public private(set) var isRefreshing = false

    /// Item waiting for user confirmation before redemption.
    public private(set) var pendingItem: ShopItem?
    /// `true` while a redeem/equip network call is in flight.
    public private(set) var isRedeeming = false
    /// Error from the most recent failed redeem. Cleared when a new redeem starts.
    public private(set) var redeemError: AppError?

    // MARK: - Dependencies

    private let repository: EngagementRepository
    nonisolated(unsafe) private var loadTask: Task<Void, Never>?
    nonisolated(unsafe) private var shopTask: Task<Void, Never>?

    // MARK: - Init

    public init(repository: EngagementRepository) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
        shopTask?.cancel()
    }

    // MARK: - Intents

    /// Called on view appear. No-op if loading has already started.
    public func load() {
        guard case .loading = loadState else { return }
        beginLoad()
    }

    /// Lazily load the shop when the Shop tab is first selected.
    public func loadShopIfNeeded() {
        guard case .idle = shopLoadState else { return }
        shopLoadState = .loading
        beginShopLoad()
    }

    /// Pull-to-refresh: re-fetches both ledger and shop in parallel.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let fp: Void = performFetch(forceRefresh: true)
        async let shop: Void = performShopFetch(forceRefresh: true)
        _ = await (fp, shop)
    }

    /// Presents the confirmation sheet for the given item.
    public func showConfirmation(for item: ShopItem) {
        redeemError = nil
        pendingItem = item
    }

    /// Dismisses the confirmation sheet without acting.
    public func dismissConfirmation() {
        pendingItem = nil
    }

    /// Called when the user taps Confirm in the sheet.
    public func confirm() {
        guard let item = pendingItem, !isRedeeming else { return }
        let captured = item
        pendingItem = nil
        Task { [weak self] in
            await self?.executeRedeem(captured)
        }
    }

    // MARK: - Computed helpers

    /// Current balance, or 0 when not yet loaded.
    public var balance: Int {
        if case .loaded(let balance, _) = loadState { return balance }
        return 0
    }

    /// Transaction ledger, oldest-first.
    public var ledger: [FlowLedgerEntry] {
        if case .loaded(_, let ledger) = loadState { return ledger }
        return []
    }

    /// All shop items.
    public var shopItems: [ShopItem] {
        if case .loaded(let items) = shopLoadState { return items }
        return []
    }

    /// Non-cosmetic reward items (book unlocks, pro passes).
    public var shopRewards: [ShopItem] {
        shopItems.filter { !$0.kind.isCosmetic }
    }

    /// Cosmetic items (themes, frames, seasonal).
    public var shopCosmetics: [ShopItem] {
        shopItems.filter { $0.kind.isCosmetic }
    }

    /// Whether the user can afford the given item.
    public func canAfford(_ item: ShopItem) -> Bool {
        balance >= item.cost
    }

    /// The action the user can take on a shop item.
    public func action(for item: ShopItem) -> ShopItemAction {
        let owned = item.isOwned ?? false
        let equipped = item.isEquipped ?? false
        switch item.kind {
        case .theme, .frame, .seasonal:
            if equipped { return .equipped }
            if owned { return .equip }
            return canAfford(item) ? .buy : .buyDisabled
        case .bonusBookUnlock, .proPass7d, .proPass30d:
            if owned { return .owned }
            return canAfford(item) ? .buy : .buyDisabled
        case .unknown:
            return .hidden
        }
    }

    // MARK: - Private

    private func beginLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performFetch(forceRefresh: false)
        }
    }

    private func beginShopLoad() {
        shopTask?.cancel()
        shopTask = Task { [weak self] in
            await self?.performShopFetch(forceRefresh: false)
        }
    }

    private func performFetch(forceRefresh: Bool) async {
        do {
            let resp = try await repository.fetchFlowPoints(forceRefresh: forceRefresh)
            loadState = .loaded(balance: resp.balance, ledger: resp.ledger ?? [])
        } catch let appErr as AppError {
            if case .loaded = loadState { return }
            loadState = .error(appErr)
        } catch {
            if case .loaded = loadState { return }
            loadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    private func performShopFetch(forceRefresh: Bool) async {
        do {
            let resp = try await repository.fetchShop(forceRefresh: forceRefresh)
            shopLoadState = .loaded(resp.items)
        } catch let appErr as AppError {
            if case .loaded = shopLoadState { return }
            shopLoadState = .error(appErr)
        } catch {
            if case .loaded = shopLoadState { return }
            shopLoadState = .error(.server(code: "unknown", message: error.localizedDescription, requestId: nil))
        }
    }

    private func executeRedeem(_ item: ShopItem) async {
        isRedeeming = true
        redeemError = nil
        defer { isRedeeming = false }

        let isEquipAction = item.kind.isCosmetic && (item.isOwned ?? false)
        let action: String? = isEquipAction ? "equip" : nil

        do {
            let response = try await repository.redeemItem(itemId: item.id, action: action)
            // Immediately surface the new balance from the response.
            let currentLedger: [FlowLedgerEntry]
            if case .loaded(_, let ledger) = loadState { currentLedger = ledger } else { currentLedger = [] }
            loadState = .loaded(balance: response.balance, ledger: currentLedger)
            // Then refresh to get the updated ledger entries and shop ownership state.
            await performFetch(forceRefresh: true)
            await performShopFetch(forceRefresh: true)
        } catch let appErr as AppError {
            redeemError = appErr
        } catch {
            redeemError = .server(code: "unknown", message: error.localizedDescription, requestId: nil)
        }
    }
}

// MARK: - ShopItemAction

/// The available action for a shop item given the current user state.
public enum ShopItemAction: Equatable {
    /// Item can be purchased (user has sufficient balance).
    case buy
    /// User cannot afford the item.
    case buyDisabled
    /// Item is owned and can be equipped (cosmetics only).
    case equip
    /// Item is already equipped (cosmetics only).
    case equipped
    /// Item has already been purchased (non-cosmetic rewards).
    case owned
    /// Item kind is unknown — hide the action button entirely.
    case hidden
}
