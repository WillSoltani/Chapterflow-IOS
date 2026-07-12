import Foundation
import StoreKit

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
    /// Introductory/trial offer display text — only populated when the user
    /// is confirmed eligible via `Product.SubscriptionInfo.isEligibleForIntroOffer`.
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

    /// Package-internal init from a live `Product`.
    ///
    /// `isEligibleForIntroOffer` gates the intro offer text: only users confirmed
    /// eligible via `Product.SubscriptionInfo.isEligibleForIntroOffer` see trial
    /// copy on the paywall. Ineligible users see regular pricing without a trial badge.
    init(product: Product, isPopular: Bool, isEligibleForIntroOffer: Bool = true) {
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

        if isEligibleForIntroOffer, let intro = product.subscription?.introductoryOffer {
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
