import Models

extension Fixtures {

    // MARK: - FREE entitlement

    /// FREE-tier entitlement with one unlocked book and 1 remaining free start.
    /// Includes a paywall configuration with monthly + annual pricing tiers.
    public static let entitlementFree: EntitlementResponse = load("entitlement_free")

    /// Convenience accessor.
    public static var entitlementFreeValue: Entitlement { entitlementFree.entitlement }

    /// The paywall shown to free users.
    public static var paywall: Paywall? { entitlementFree.paywall }

    // MARK: - PRO entitlement

    /// PRO-tier entitlement (active Apple subscription, no paywall).
    public static let entitlementPro: EntitlementResponse = load("entitlement_pro")

    /// Convenience accessor.
    public static var entitlementProValue: Entitlement { entitlementPro.entitlement }
}
