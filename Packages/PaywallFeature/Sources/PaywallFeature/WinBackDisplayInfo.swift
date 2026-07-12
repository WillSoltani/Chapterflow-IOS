import StoreKit

/// Display-friendly representation of a StoreKit win-back offer.
///
/// Contains only value types so it is Sendable and preview-safe. The live
/// StoreKit objects are retained internally by `PaywallModel` for purchase time.
public struct WinBackDisplayInfo: Sendable, Equatable {
    public let productID: String
    public let productDisplayName: String
    public let offerDisplayPrice: String
    public let offerPeriodText: String
    public let regularDisplayPrice: String
    public let regularPeriodLabel: String
    public let paymentMode: PaymentModeKind
    public let offerID: String

    public enum PaymentModeKind: Sendable, Equatable {
        case freeTrial, payUpFront, payAsYouGo
    }

    public var fullDescription: String {
        switch paymentMode {
        case .freeTrial:
            return "\(offerPeriodText) free, then \(regularDisplayPrice)/\(regularPeriodLabel)"
        case .payUpFront, .payAsYouGo:
            return "\(offerDisplayPrice) for \(offerPeriodText), then \(regularDisplayPrice)/\(regularPeriodLabel)"
        }
    }

    public init(
        productID: String,
        productDisplayName: String,
        offerDisplayPrice: String,
        offerPeriodText: String,
        regularDisplayPrice: String,
        regularPeriodLabel: String,
        paymentMode: PaymentModeKind,
        offerID: String
    ) {
        self.productID = productID
        self.productDisplayName = productDisplayName
        self.offerDisplayPrice = offerDisplayPrice
        self.offerPeriodText = offerPeriodText
        self.regularDisplayPrice = regularDisplayPrice
        self.regularPeriodLabel = regularPeriodLabel
        self.paymentMode = paymentMode
        self.offerID = offerID
    }

    init(product: Product, offer: Product.SubscriptionOffer) {
        productID = product.id
        productDisplayName = product.displayName
        offerDisplayPrice = offer.displayPrice
        regularDisplayPrice = product.displayPrice
        offerID = offer.id ?? ""

        let offerPeriod = offer.period
        switch offerPeriod.unit {
        case .day: offerPeriodText = offerPeriod.value == 1 ? "1 day" : "\(offerPeriod.value) days"
        case .week: offerPeriodText = offerPeriod.value == 1 ? "1 week" : "\(offerPeriod.value) weeks"
        case .month: offerPeriodText = offerPeriod.value == 1 ? "1 month" : "\(offerPeriod.value) months"
        case .year: offerPeriodText = offerPeriod.value == 1 ? "1 year" : "\(offerPeriod.value) years"
        @unknown default: offerPeriodText = "\(offerPeriod.value) periods"
        }

        if let subscriptionPeriod = product.subscription?.subscriptionPeriod {
            switch subscriptionPeriod.unit {
            case .day: regularPeriodLabel = "day"
            case .week: regularPeriodLabel = "week"
            case .month: regularPeriodLabel = "month"
            case .year: regularPeriodLabel = "year"
            @unknown default: regularPeriodLabel = "period"
            }
        } else {
            regularPeriodLabel = "period"
        }

        switch offer.paymentMode {
        case .freeTrial: paymentMode = .freeTrial
        case .payAsYouGo: paymentMode = .payAsYouGo
        default: paymentMode = .payUpFront
        }
    }
}
