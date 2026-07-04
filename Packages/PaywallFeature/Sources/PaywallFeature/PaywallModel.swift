import SwiftUI
import StoreKit
import CoreKit
import Models
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Product display wrapper

/// Display-friendly representation of a StoreKit product.
///
/// Separates the display data (usable in previews and tests) from the
/// live `Product` reference (needed only at purchase time).
public struct StoreProductInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    /// Period label such as "month" or "year".
    public let periodLabel: String
    /// Whether this is the popular/recommended pick.
    public let isPopular: Bool
    /// Introductory/trial offer display text, if available.
    public let introductoryOfferText: String?
    /// The raw decimal price value — used for savings-badge calculation. Nil in
    /// preview / test stubs where a live `Product` is unavailable.
    public let priceDecimalValue: Decimal?

    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        periodLabel: String,
        isPopular: Bool,
        introductoryOfferText: String? = nil,
        priceDecimalValue: Decimal? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodLabel = periodLabel
        self.isPopular = isPopular
        self.introductoryOfferText = introductoryOfferText
        self.priceDecimalValue = priceDecimalValue
    }

    init(product: Product, isPopular: Bool) {
        self.id = product.id
        self.displayName = product.displayName
        self.displayPrice = product.displayPrice
        self.isPopular = isPopular

        if let period = product.subscription?.subscriptionPeriod {
            switch period.unit {
            case .day:   self.periodLabel = period.value == 1 ? "day" : "\(period.value) days"
            case .week:  self.periodLabel = period.value == 1 ? "week" : "\(period.value) weeks"
            case .month: self.periodLabel = period.value == 1 ? "month" : "\(period.value) months"
            case .year:  self.periodLabel = period.value == 1 ? "year" : "\(period.value) years"
            @unknown default: self.periodLabel = "period"
            }
        } else {
            self.periodLabel = "one-time"
        }

        self.priceDecimalValue = product.price

        if let intro = product.subscription?.introductoryOffer {
            switch intro.paymentMode {
            case .freeTrial:
                self.introductoryOfferText = "Free \(intro.period.value)-\(intro.period.unit.singular) trial"
            case .payAsYouGo, .payUpFront:
                self.introductoryOfferText = "\(intro.displayPrice) intro offer"
            default:
                self.introductoryOfferText = nil
            }
        } else {
            self.introductoryOfferText = nil
        }
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var singular: String {
        switch self {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        @unknown default: return "period"
        }
    }
}

// MARK: - Purchase state

/// The in-flight state of a purchase initiated from the paywall.
public enum PurchaseState: Sendable, Equatable {
    case idle
    case purchasing
    case restoring
    /// A deferred purchase (Ask-to-Buy) is waiting for parental approval.
    case pendingApproval
    /// Purchase completed successfully — show celebration before dismissing.
    case success(productID: String)
    case failed(String)  // localizedDescription

    public var isInProgress: Bool {
        switch self {
        case .purchasing, .restoring: return true
        default: return false
        }
    }
}

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
    public private(set) var purchaseState: PurchaseState = .idle
    public private(set) var isLoadingProducts = false
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

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol
    private let analytics: any AnalyticsClient

    /// Live `Product` objects keyed by product ID, used at purchase time.
    private var liveProducts: [String: Product] = [:]

    /// Cancels the entitlement-change listener when the model is torn down.
    /// `nonisolated(unsafe)` allows `deinit` to cancel it without hopping to the main actor.
    /// Safe: only written from `startListening()` (always @MainActor); `deinit` runs
    /// after all strong references are gone so there is no concurrent writer at that point.
    nonisolated(unsafe) private var entitlementListenerTask: Task<Void, Never>?

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
    }

    /// Injects pre-built state for Xcode Previews and unit tests.
    func inject(
        productInfos: [StoreProductInfo],
        status: SubscriptionStatus,
        proSource: String? = nil,
        serverBenefits: [String]? = nil
    ) {
        self.productInfos = productInfos
        self.subscriptionStatus = status
        self.proSource = proSource
        self.serverBenefits = serverBenefits
    }

    deinit {
        entitlementListenerTask?.cancel()
    }

    // MARK: - On-appear

    /// Call once from `PaywallView.task`. Loads products, fetches server paywall
    /// data, and fires the `paywall_viewed` analytics event.
    public func onAppear() async {
        analytics.track(.paywallViewed(source: context.analyticsSource))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProducts() }
            group.addTask { await self.fetchServerPaywall() }
            group.addTask { await self.refreshEntitlement() }
        }
        if selectedProductID == nil {
            selectedProductID = productInfos.first?.id
        }
    }

    // MARK: - Selected product (exposed so views can bind)

    public private(set) var selectedProductID: String?

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
        guard entitlementListenerTask == nil else { return }
        let stream = storeKitService.entitlementChanges
        entitlementListenerTask = Task { [weak self] in
            for await _ in stream {
                await self?.refreshEntitlement()
            }
        }
    }

    // MARK: - Product loading

    /// Fetches products from the App Store and populates `productInfos`.
    public func loadProducts() async {
        isLoadingProducts = true
        errorMessage = nil
        defer { isLoadingProducts = false }

        do {
            let products = try await storeKitService.loadProducts()
            liveProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            productInfos = products.map { product in
                // Mark the first product (typically annual) as popular.
                StoreProductInfo(product: product, isPopular: products.first?.id == product.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    // MARK: - Purchase

    /// Initiates a purchase for the product with `productID`.
    public func purchase(productID: String) async {
        guard let product = liveProducts[productID] else {
            errorMessage = "Product unavailable. Please try again."
            return
        }
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await storeKitService.purchase(product)
            switch result {
            case .purchased:
                analytics.track(.purchase(productId: productID))
                await refreshEntitlement()
                purchaseState = .success(productID: productID)
            case .pending:
                purchaseState = .pendingApproval
            case .userCancelled:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Restore

    /// Restores prior purchases.
    public func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil
        do {
            try await storeKitService.restorePurchases()
            await refreshEntitlement()
            if subscriptionStatus.isPro {
                purchaseState = .success(productID: "")
            } else {
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
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
        do {
            // 1. Refresh local StoreKit status (grace period, billing retry, etc.)
            let storeStatus = try await storeKitService.currentSubscriptionStatus()

            // 2. Re-fetch the backend entitlement so gating reflects the server truth.
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())
            let entitlement = response.entitlement

            // Backend plan is authoritative for gating; StoreKit state surfaces
            // billing-lifecycle detail (grace period, billing retry).
            let backendIsPro = entitlement.plan == .pro && entitlement.proStatus == "active"
            if backendIsPro {
                // When backend confirms pro, prefer StoreKit state so billing-UI
                // banners (grace period, billing retry) are surfaced correctly.
                subscriptionStatus = storeStatus.isPro ? storeStatus : .subscribed(productID: "", expirationDate: nil)
                proSource = entitlement.proSource
            } else {
                subscriptionStatus = .notSubscribed
                proSource = nil
            }
        } catch {
            // Keep the last known status on refresh failure to avoid flickering.
        }
    }
}
