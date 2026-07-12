import Foundation
import CoreKit

public enum StoreKitConfigurationIssue: String, Sendable, Equatable, CaseIterable {
    case missingMonthlyProduct
    case missingAnnualProduct
    case unsupportedAnnualUpfrontProduct
    case malformedProductID
    case duplicateProductID
}

/// StoreKit product ID configuration, derived from `AppConfig`.
///
/// Product IDs must match exactly what is configured in App Store Connect
/// for the subscription group. Never hardcode literals — always read from here.
public struct StoreKitConfig: Sendable, Equatable {

    /// Product ID for the monthly auto-renewable subscription.
    public let monthlyProductID: String
    /// Product ID for the annual auto-renewable subscription.
    public let annualProductID: String
    /// Reserved product ID for a future annual-upfront (non-renewing) product.
    /// This must remain empty until the backend can verify that product type.
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

    /// Supported recurring product IDs to pass to `Product.products(for:)`.
    /// The reserved upfront ID is deliberately excluded from the purchase catalog.
    public var allProductIDs: Set<String> {
        var ids: Set<String> = []
        if !monthlyProductID.isEmpty { ids.insert(monthlyProductID) }
        if !annualProductID.isEmpty { ids.insert(annualProductID) }
        return ids
    }

    /// Safe structural validation performed before StoreKit is contacted.
    /// Production allowlist membership is enforced by the release preflight;
    /// this layer prevents empty, malformed, duplicate, or unsupported queries.
    public var validationIssues: [StoreKitConfigurationIssue] {
        var issues: [StoreKitConfigurationIssue] = []
        if monthlyProductID.isEmpty { issues.append(.missingMonthlyProduct) }
        if annualProductID.isEmpty { issues.append(.missingAnnualProduct) }
        if !annualUpfrontProductID.isEmpty {
            issues.append(.unsupportedAnnualUpfrontProduct)
        }

        let configuredIDs = [monthlyProductID, annualProductID, annualUpfrontProductID]
            .filter { !$0.isEmpty }
        if configuredIDs.contains(where: { !Self.isStructurallyValidProductID($0) }) {
            issues.append(.malformedProductID)
        }
        if Set(configuredIDs).count != configuredIDs.count {
            issues.append(.duplicateProductID)
        }
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }

    /// Creates a `StoreKitConfig` from the shared `AppConfig`.
    public static func from(_ config: AppConfig) -> StoreKitConfig {
        StoreKitConfig(
            monthlyProductID: config.storeKitMonthlyProductID,
            annualProductID: config.storeKitAnnualProductID,
            annualUpfrontProductID: config.storeKitAnnualUpfrontProductID
        )
    }

    private static func isStructurallyValidProductID(_ productID: String) -> Bool {
        let range = NSRange(productID.startIndex..., in: productID)
        let pattern = #"^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)+$"#
        return (try? NSRegularExpression(pattern: pattern).firstMatch(
            in: productID,
            range: range
        )) != nil
    }
}
