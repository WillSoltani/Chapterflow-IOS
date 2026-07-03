import SwiftUI
import StoreKit
import CoreKit
import Models
import Networking

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

    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        periodLabel: String,
        isPopular: Bool,
        introductoryOfferText: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodLabel = periodLabel
        self.isPopular = isPopular
        self.introductoryOfferText = introductoryOfferText
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
/// Owned by the composition root (AppModel) and injected into the SwiftUI
/// environment so any view can access the current subscription status.
@Observable
@MainActor
public final class PaywallModel {

    // MARK: - Public state

    public private(set) var productInfos: [StoreProductInfo] = []
    public private(set) var subscriptionStatus: SubscriptionStatus = .unknown
    public private(set) var purchaseState: PurchaseState = .idle
    public private(set) var isLoadingProducts = false
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let storeKitService: any StoreKitServicing
    private let apiClient: any APIClientProtocol

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
        initialProductInfos: [StoreProductInfo] = [],
        initialStatus: SubscriptionStatus = .unknown
    ) {
        self.storeKitService = storeKitService
        self.apiClient = apiClient
        self.productInfos = initialProductInfos
        self.subscriptionStatus = initialStatus
    }

    /// Injects pre-built state for Xcode Previews and unit tests.
    func inject(productInfos: [StoreProductInfo], status: SubscriptionStatus) {
        self.productInfos = productInfos
        self.subscriptionStatus = status
    }

    deinit {
        entitlementListenerTask?.cancel()
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
                purchaseState = .idle
                await refreshEntitlement()
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
            purchaseState = .idle
            await refreshEntitlement()
        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Entitlement refresh

    /// Fetches the latest subscription status from StoreKit and the backend entitlement.
    ///
    /// The backend entitlement is authoritative for gating — this keeps the local
    /// `subscriptionStatus` in sync with the server view, which may differ when
    /// the user subscribes via a different platform (web/Stripe).
    public func refreshEntitlement() async {
        do {
            // 1. Refresh local StoreKit status (grace period, billing retry, etc.)
            let storeStatus = try await storeKitService.currentSubscriptionStatus()

            // 2. Re-fetch the backend entitlement so gating reflects the server truth.
            let response: EntitlementResponse = try await apiClient.send(Endpoints.getEntitlements())

            // Backend plan is authoritative for gating; StoreKit state surfaces
            // billing-lifecycle detail (grace period, billing retry).
            let isPro = response.entitlement.plan == .pro
            if isPro {
                // When backend confirms pro, prefer StoreKit state so billing-UI
                // banners (grace period, billing retry) are surfaced correctly.
                subscriptionStatus = storeStatus.isPro ? storeStatus : .subscribed(productID: "", expirationDate: nil)
            } else {
                subscriptionStatus = .notSubscribed
            }
        } catch {
            // Keep the last known status on refresh failure to avoid flickering.
        }
    }
}
