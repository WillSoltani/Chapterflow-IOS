/// Paywall configuration returned alongside the entitlement.
///
/// Drives the upgrade screen UI without requiring a separate network call.
public struct Paywall: Codable, Sendable {
    public let price: String
    public let pricingTiers: [PricingTier]
    public let benefits: [String]
}

/// A single pricing option displayed on the upgrade screen.
public struct PricingTier: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let price: String?
    public let period: String?
    public let isPopular: Bool?
}
