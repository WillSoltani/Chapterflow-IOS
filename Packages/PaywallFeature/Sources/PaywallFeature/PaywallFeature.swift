/// PaywallFeature — StoreKit 2 service, entitlement model, and paywall UI.
///
/// Public surface:
/// - `StoreKitService` (actor) — purchases, Transaction.updates listener, backend verify
/// - `StoreKitServicing` — protocol abstraction for testing
/// - `StoreKitConfig` — product IDs read from `AppConfig`
/// - `SubscriptionStatus` — current subscription lifecycle state
/// - `PurchaseResult`, `PurchaseState`, `StoreKitServiceError` — typed outcomes
/// - `StoreProductInfo` — display data (usable in previews without real StoreKit)
/// - `PaywallModel` (`@Observable @MainActor`) — drives `PaywallView`
/// - `PaywallView` — the upgrade sheet presented from any feature package
public enum PaywallFeatureModule {
    /// Module name — useful as a smoke-test symbol.
    public static let moduleName = "PaywallFeature"
}
