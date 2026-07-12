/// Whether the paywall has a verified set of purchasable StoreKit products.
///
/// This is intentionally separate from purchase errors. A missing production
/// configuration must never degrade into an apparently actionable Subscribe
/// button, and transient StoreKit/network failures need a safe retry path.
public enum ProductAvailabilityState: Sendable, Equatable {
    case idle
    case loading
    case available
    case configurationInvalid
    case networkUnavailable
    case storeUnavailable

    public var canRetry: Bool {
        switch self {
        case .networkUnavailable, .storeUnavailable:
            return true
        case .idle, .loading, .available, .configurationInvalid:
            return false
        }
    }

    public var userMessage: String {
        switch self {
        case .idle, .loading, .available:
            return ""
        case .configurationInvalid:
            return "Subscriptions are not configured for this version of ChapterFlow."
        case .networkUnavailable:
            return "Connect to the internet to load subscription options."
        case .storeUnavailable:
            return "Subscription options are unavailable right now. Please try again later."
        }
    }
}
