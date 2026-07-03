import CoreKit

/// StoreKit product ID configuration, derived from `AppConfig`.
///
/// Product IDs must match exactly what is configured in App Store Connect
/// for the subscription group. Never hardcode literals — always read from here.
public struct StoreKitConfig: Sendable, Equatable {

    /// Product ID for the monthly auto-renewable subscription.
    public let monthlyProductID: String
    /// Product ID for the annual auto-renewable subscription.
    public let annualProductID: String
    /// Product ID for the optional annual-upfront (non-renewing) product.
    /// Empty string means this tier is not offered.
    public let annualUpfrontProductID: String

    public init(
        monthlyProductID: String,
        annualProductID: String,
        annualUpfrontProductID: String = ""
    ) {
        self.monthlyProductID = monthlyProductID
        self.annualProductID = annualProductID
        self.annualUpfrontProductID = annualUpfrontProductID
    }

    /// All non-empty product IDs to pass to `Product.products(for:)`.
    public var allProductIDs: Set<String> {
        var ids: Set<String> = []
        if !monthlyProductID.isEmpty { ids.insert(monthlyProductID) }
        if !annualProductID.isEmpty { ids.insert(annualProductID) }
        if !annualUpfrontProductID.isEmpty { ids.insert(annualUpfrontProductID) }
        return ids
    }

    /// Creates a `StoreKitConfig` from the shared `AppConfig`.
    public static func from(_ config: AppConfig) -> StoreKitConfig {
        StoreKitConfig(
            monthlyProductID: config.storeKitMonthlyProductID,
            annualProductID: config.storeKitAnnualProductID,
            annualUpfrontProductID: config.storeKitAnnualUpfrontProductID
        )
    }
}
