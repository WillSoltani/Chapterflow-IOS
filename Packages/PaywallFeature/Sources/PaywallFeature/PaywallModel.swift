import SwiftUI
import StoreKit
import CoreKit
import Models
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PaywallModel

/// Observable model driving `PaywallView` and any gating presentation.
///
/// Owns the full paywall lifecycle: loads StoreKit products, fetches the
/// server's `paywall` object (benefits copy + pricing tiers), tracks analytics,
/// drives the purchase / restore flows, and exposes a `success` state so the
/// view can play a celebration before auto-dismissing.
@Observable
@MainActor
public final class PaywallModel {

    // MARK: - Public state

    public private(set) var productInfos: [StoreProductInfo] = []
    public private(set) var subscriptionStatus: SubscriptionStatus = .unknown
    public private(set) var entitlementResolution: EntitlementResolutionState = .unresolved
    public private(set) var purchaseState: PurchaseState = .idle
    public private(set) var isLoadingProducts = false
    public private(set) var productAvailability: ProductAvailabilityState = .idle
    public private(set) var errorMessage: String?
    /// Benefits copy from the server's paywall object; `nil` while loading or
    /// on offline/error — the view falls back to the hardcoded ProBenefit set.
    public private(set) var serverBenefits: [String]?
    /// The presentation context injected at init time.
    public let context: PaywallContext
    /// The raw `proSource` field from the backend entitlement.
    ///
    /// Common values: `"stripe"`, `"apple"`, `"license"`, `"gift_code"`, `"admin"`.
    /// `nil` when the user is on the free tier or the entitlement hasn't loaded yet.
    /// Used by the paywall to show source-specific "already Pro" messaging.
    public private(set) var proSource: String?

    /// Product IDs for which the current user is eligible for an introductory offer.
    /// Populated by `loadProducts()` via `StoreKitService.introOfferEligibleProductIDs()`.
    public private(set) var eligibleIntroOfferProductIDs: Set<String> = []

    /// Win-back offer available for this lapsed user, or `nil` when not applicable.
    /// Shown when `subscriptionStatus` is `.expired` or `.revoked`.
    public private(set) var winBackDisplay: WinBackDisplayInfo? = nil

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let analytics: any AnalyticsClient

    /// Live `Product` objects keyed by product ID, used at purchase time.
    private var liveProducts: [String: Product] = [:]
    private var entitlementRefreshGeneration = 0
    private var lastStableEntitlementResolution: EntitlementResolutionState = .unresolved
    /// A `.purchased(proSource:)` result is a backend-authoritative active Pro
    /// acknowledgement. Keep it until the entitlement read endpoint has
    /// observed Pro so a lagging response cannot re-enable purchasing. The
    /// source comes from the backend and is never assumed to be Apple.
    private var isAwaitingPurchasedGrantReadback = false
    private(set) var activeBillingAction: BillingAction?

    /// Cancels the entitlement-change listener when the model is torn down.
    private let entitlementListenerTaskHandle = TaskCancellationHandle()

    // MARK: - Init

    public init(
        storeKitService: any StoreKitServicing,
        apiClient: any APIClientProtocol,
        analytics: any AnalyticsClient = NoopAnalyticsClient(),
        context: PaywallContext = .settings,
        initialProductInfos: [StoreProductInfo] = [],
        initialStatus: SubscriptionStatus = .unknown
    ) {
        self.storeKitService = storeKitService
        self.apiClient = apiClient
        self.analytics = analytics
        self.context = context
        self.productInfos = initialProductInfos
        self.subscriptionStatus = initialStatus
        self.entitlementResolution = .unresolved
        self.productAvailability = initialProductInfos.isEmpty ? .idle : .available
    }

    /// Injects pre-built state for Xcode Previews and unit tests.
    func inject(
        productInfos: [StoreProductInfo],
        status: SubscriptionStatus,
        entitlementResolution: EntitlementResolutionState,
        proSource: String? = nil,
        serverBenefits: [String]? = nil,
        winBackDisplay: WinBackDisplayInfo? = nil,
        productAvailability: ProductAvailabilityState? = nil
    ) {
        self.productInfos = productInfos
        self.subscriptionStatus = status
        self.entitlementResolution = entitlementResolution
        if entitlementResolution != .resolving {
            self.lastStableEntitlementResolution = entitlementResolution
        }
        self.isAwaitingPurchasedGrantReadback = false
        self.proSource = proSource
        self.serverBenefits = serverBenefits
        self.winBackDisplay = winBackDisplay
        self.productAvailability = productAvailability ?? (productInfos.isEmpty ? .idle : .available)
    }

    deinit {
        entitlementListenerTaskHandle.cancel()
    }

    // MARK: - On-appear

    /// Call once from `PaywallView.task`. Loads products, fetches server paywall
    /// data, fires the `paywall_viewed` analytics event, and checks offer eligibility.
    public func onAppear() async {
        analytics.track(.paywallViewed(source: context.analyticsSource))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProducts() }
            group.addTask { await self.fetchServerPaywall() }
            group.addTask { await self.refreshEntitlement() }
            group.addTask { await self.fetchWinBackDisplay() }
        }
        if selectedProductID == nil {
            selectedProductID = productInfos.first?.id
        }
    }

    // MARK: - Selected product (exposed so views can bind)

    public private(set) var selectedProductID: String?

    /// Purchases remain disabled until the backend has authoritatively confirmed
    /// this account is free, even if StoreKit prices have already loaded.
    public var canPurchase: Bool {
        entitlementResolution.permitsPurchase
            && purchaseState.permitsNewBillingAction
            && activeBillingAction == nil
            && productAvailability == .available
            && selectedProductID != nil
    }

    // MARK: - Savings

    /// Percentage saved on the annual plan vs paying monthly for 12 months.
    /// Returns `nil` when both products aren't loaded or prices are unavailable.
    public var annualSavingsPercent: Int? {
        guard let annual = productInfos.first(where: { $0.periodLabel == "year" }),
              let monthly = productInfos.first(where: { $0.periodLabel == "month" }),
              let annualPrice = annual.priceDecimalValue,
              let monthlyPrice = monthly.priceDecimalValue,
              monthlyPrice > 0 else { return nil }
        let twelveMonths = monthlyPrice * 12
        guard twelveMonths > annualPrice else { return nil }
        let ratio = NSDecimalNumber(decimal: (twelveMonths - annualPrice) / twelveMonths).doubleValue
        let pct = Int(ratio * 100)
        return pct > 0 ? pct : nil
    }

    public func selectProduct(_ productID: String) {
        selectedProductID = productID
    }

    // MARK: - Lifecycle

    /// Begins observing `StoreKitService.entitlementChanges` and refreshes the
    /// entitlement from the backend whenever StoreKit signals a change.
    /// Call once on `onAppear` / app launch.
    public func startListening() {
        let storeKitService = storeKitService
        entitlementListenerTaskHandle.installIfEmpty(
            Task { [weak self, storeKitService] in
                let stream = await storeKitService.entitlementChanges()
                for await _ in stream {
                    await self?.refreshEntitlement()
                }
            }
        )
    }

    // MARK: - Product loading

    /// Fetches products from the App Store, checks intro-offer eligibility, and
    /// populates `productInfos`. Only eligible users see trial/intro pricing.
    public func loadProducts() async {
        guard !isLoadingProducts else { return }
        let hadUsableProducts = !productInfos.isEmpty && !liveProducts.isEmpty
        isLoadingProducts = true
        errorMessage = nil
        if !hadUsableProducts {
            productAvailability = .loading
            clearProducts()
        }
        defer { isLoadingProducts = false }

        do {
            let products = try await storeKitService.loadProducts()
            try Task.checkCancellation()
            guard !products.isEmpty else {
                clearProducts()
                productAvailability = .storeUnavailable
                return
            }
            let eligibleIDs = await storeKitService.introOfferEligibleProductIDs()
            try Task.checkCancellation()
            liveProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            eligibleIntroOfferProductIDs = eligibleIDs
            productInfos = products.map { product in
                StoreProductInfo(
                    product: product,
                    isPopular: products.first?.id == product.id,
                    isEligibleForIntroOffer: eligibleIDs.contains(product.id)
                )
            }
            selectedProductID = productInfos.first?.id
            productAvailability = .available
        } catch {
            if Task.isCancelled || Self.isCancellation(error) {
                productAvailability = hadUsableProducts ? .available : .idle
                return
            }

            let failureState = Self.availabilityState(for: error)
            if hadUsableProducts, failureState != .configurationInvalid {
                productAvailability = .available
                errorMessage = "Couldn't refresh subscription options. Showing the last loaded prices."
            } else {
                clearProducts()
                productAvailability = failureState
            }
        }
    }

    private func clearProducts() {
        productInfos = []
        liveProducts = [:]
        eligibleIntroOfferProductIDs = []
        selectedProductID = nil
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let networkError = storeKitNetworkError(from: error) {
            return networkError.code == .cancelled
        }
        return (error as? URLError)?.code == .cancelled
    }

    private static func availabilityState(for error: any Error) -> ProductAvailabilityState {
        if let storeKitError = error as? StoreKitServiceError {
            switch storeKitError {
            case .invalidConfiguration, .productNotConfigured:
                return .configurationInvalid
            case .noProductsFound, .unverified, .accountBindingUnavailable,
                 .accountBindingMismatch, .accountChangedDuringVerification,
                 .unsupportedOwnership, .transactionNotActive,
                 .processedWithoutActiveEntitlement:
                return .storeUnavailable
            }
        }

        if let appError = error as? AppError, case .offline = appError {
            return .networkUnavailable
        }
        if storeKitNetworkError(from: error) != nil {
            return .networkUnavailable
        }
        if error is URLError {
            return .networkUnavailable
        }
        return .storeUnavailable
    }

    // MARK: - Server paywall data

    /// Fetches the backend `paywall` object (benefits copy + pricing-tier metadata).
    /// Failure is non-fatal — the view falls back to hardcoded benefits.
    private func fetchServerPaywall() async {
        do {
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            if let paywall = response.paywall, !paywall.benefits.isEmpty {
                serverBenefits = paywall.benefits
            }
        } catch {
            // Non-fatal — hardcoded benefits remain in place.
        }
    }

    // MARK: - Win-back offer

    /// Fetches the best eligible win-back offer for lapsed users.
    private func fetchWinBackDisplay() async {
        winBackDisplay = await storeKitService.winBackDisplayInfo()
    }

    // MARK: - Purchase

    /// Initiates a standard purchase for the product with `productID`.
    public func purchase(productID: String) async {
        guard activeBillingAction == nil else { return }
        guard entitlementResolution.permitsPurchase else {
            errorMessage = Self.entitlementRequiredMessage(for: entitlementResolution)
            return
        }
        guard let product = liveProducts[productID] else {
            errorMessage = "Product unavailable. Please try again."
            return
        }
        guard beginBillingAction(.purchase) else { return }
        defer { endBillingAction(.purchase) }
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await storeKitService.purchase(product)
            handlePurchaseResult(result, productID: productID)
        } catch {
            handleBillingFailure(error)
        }
    }

    /// Purchases the available win-back offer.
    ///
    /// No-ops gracefully if no win-back offer is cached (e.g. user became ineligible
    /// between loading and tapping).
    public func purchaseWinBack() async {
        guard activeBillingAction == nil else { return }
        guard entitlementResolution.permitsPurchase else {
            errorMessage = Self.entitlementRequiredMessage(for: entitlementResolution)
            return
        }
        guard let info = winBackDisplay, !info.offerID.isEmpty else {
            errorMessage = "Win-back offer is no longer available. Please try again."
            return
        }
        guard beginBillingAction(.winBack) else { return }
        defer { endBillingAction(.winBack) }
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await storeKitService.purchaseWithWinBack(
                productID: info.productID,
                offerID: info.offerID
            )
            handlePurchaseResult(result, productID: info.productID)
        } catch {
            handleBillingFailure(error)
        }
    }

    // MARK: - Restore

    /// Restores prior purchases.
    public func restorePurchases() async {
        guard beginBillingAction(.restore) else { return }
        defer { endBillingAction(.restore) }
        purchaseState = .restoring
        errorMessage = nil
        do {
            try await storeKitService.restorePurchases()
            await refreshEntitlement()
            if entitlementResolution == .resolvedPro {
                purchaseState = .success(productID: "")
            } else if entitlementResolution == .resolvedFree {
                let message = "No previous purchases were found for this ChapterFlow account."
                purchaseState = .failed(message)
                errorMessage = message
            } else {
                let message = "We couldn't confirm restored purchases. Check your connection and try again."
                purchaseState = .failed(message)
                errorMessage = message
            }
        } catch {
            handleBillingFailure(error)
        }
    }

    // MARK: - Manage subscription

    /// Opens the App Store subscription management page.
    public func openManageSubscriptions() {
        #if canImport(UIKit)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        Task {
            await UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Entitlement refresh

    /// Fetches the latest subscription status from StoreKit and the backend entitlement.
    ///
    /// The backend entitlement is authoritative for gating — this keeps the local
    /// `subscriptionStatus` in sync with the server view, which may differ when
    /// the user subscribes via a different platform (web/Stripe).
    ///
    /// Also updates `proSource` so the paywall can show source-specific "already Pro"
    /// messaging (e.g. "Pro via web" for Stripe users).
    ///
    /// **Never double-charges:** if the backend confirms Pro (any source),
    /// `subscriptionStatus.isPro` is `true` and the paywall guard prevents
    /// presenting the purchase flow.
    public func refreshEntitlement() async {
        entitlementRefreshGeneration += 1
        let generation = entitlementRefreshGeneration
        let stableResolution = lastStableEntitlementResolution
        if stableResolution == .unresolved || stableResolution == .unavailable {
            entitlementResolution = .resolving
        }

        do {
            async let storeStatusResult = try? await storeKitService.currentSubscriptionStatus()
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            try Task.checkCancellation()
            let storeStatus = await storeStatusResult ?? .unknown
            try Task.checkCancellation()
            guard generation == entitlementRefreshGeneration else { return }
            let entitlement = response.entitlement

            // Backend plan is authoritative for gating; StoreKit state surfaces
            // billing-lifecycle detail (grace period, billing retry).
            let backendIsPro = entitlement.plan == .pro && entitlement.proStatus == "active"
            let storeKitEnded = Self.isEndedAppleSubscription(storeStatus)
            if backendIsPro {
                isAwaitingPurchasedGrantReadback = false
                subscriptionStatus = Self.billingLifecycleStatus(for: storeStatus)
                proSource = entitlement.proSource
                commitStableEntitlementResolution(.resolvedPro)
                if purchaseState == .pendingApproval || purchaseState == .confirmingAccess {
                    purchaseState = .success(productID: storeStatus.activeProductIds.first ?? "")
                    errorMessage = nil
                }
            } else if isAwaitingPurchasedGrantReadback, !storeKitEnded {
                // `StoreKitServicing.purchased` is issued only after this same
                // backend acknowledged active Pro. Preserve that newer fact
                // until the read endpoint catches up; this also prevents a
                // duplicate purchase from being offered during propagation.
                commitStableEntitlementResolution(.resolvedPro)
            } else {
                isAwaitingPurchasedGrantReadback = false
                subscriptionStatus = storeKitEnded ? storeStatus : .notSubscribed
                proSource = nil
                commitStableEntitlementResolution(.resolvedFree)
                if case .success = purchaseState {
                    purchaseState = .idle
                }
            }
        } catch {
            guard generation == entitlementRefreshGeneration else { return }
            if Task.isCancelled || Self.isCancellation(error) {
                entitlementResolution = stableResolution
            } else if stableResolution == .resolvedPro {
                commitStableEntitlementResolution(.resolvedPro)
            } else {
                commitStableEntitlementResolution(.unavailable)
            }
        }
    }

    private func commitStableEntitlementResolution(_ resolution: EntitlementResolutionState) {
        guard resolution != .resolving else { return }
        entitlementResolution = resolution
        lastStableEntitlementResolution = resolution
    }

    private static func billingLifecycleStatus(for storeStatus: SubscriptionStatus) -> SubscriptionStatus {
        switch storeStatus {
        case .unknown, .notSubscribed:
            return .subscribed(productID: "", expirationDate: nil)
        case .subscribed, .pending, .inGracePeriod, .inBillingRetry, .revoked, .expired:
            return storeStatus
        }
    }

    private static func isEndedAppleSubscription(_ storeStatus: SubscriptionStatus) -> Bool {
        switch storeStatus {
        case .revoked, .expired:
            return true
        case .unknown, .notSubscribed, .subscribed, .pending, .inGracePeriod, .inBillingRetry:
            return false
        }
    }

    private func beginBillingAction(_ action: BillingAction) -> Bool {
        guard activeBillingAction == nil,
              purchaseState.permitsNewBillingAction else {
            return false
        }
        activeBillingAction = action
        return true
    }

    private func endBillingAction(_ action: BillingAction) {
        guard activeBillingAction == action else { return }
        activeBillingAction = nil
    }

    /// Applies the documented `StoreKitServicing` result contract. Package
    /// visibility keeps the state transition deterministic and directly
    /// testable without constructing an opaque StoreKit `Product` fixture.
    func handlePurchaseResult(_ result: PurchaseResult, productID: String) {
        switch result {
        case .purchased(let authoritativeProSource):
            // Invalidate any entitlement GET that began before the backend
            // purchase acknowledgement returned.
            entitlementRefreshGeneration += 1
            isAwaitingPurchasedGrantReadback = true
            analytics.track(.purchase(productId: productID))
            subscriptionStatus = .subscribed(productID: productID, expirationDate: nil)
            proSource = authoritativeProSource
            commitStableEntitlementResolution(.resolvedPro)
            purchaseState = .success(productID: productID)
            errorMessage = nil
        case .pending:
            purchaseState = .pendingApproval
        case .userCancelled:
            purchaseState = .idle
        }
    }

    private func handleBillingFailure(_ error: any Error) {
        guard !Task.isCancelled, !Self.isCancellation(error) else {
            purchaseState = .idle
            errorMessage = nil
            return
        }
        let message = Self.safeBillingErrorMessage(for: error)
        purchaseState = .failed(message)
        errorMessage = message
    }

    private static func entitlementRequiredMessage(
        for state: EntitlementResolutionState
    ) -> String {
        switch state {
        case .resolvedPro:
            return "This account already has Pro access."
        case .unresolved, .resolving, .unavailable, .resolvedFree:
            return "We need to confirm your membership before starting a purchase. Check your connection and try again."
        }
    }

}
