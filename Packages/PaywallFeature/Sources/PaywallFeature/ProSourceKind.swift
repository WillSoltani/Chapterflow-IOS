/// Classifies the raw backend `proSource` string for source-specific UI display.
///
/// The paywall uses this to show "already Pro via web" messaging for non-Apple
/// sources (Stripe, license, gift, etc.) and the App Store manage-subscription
/// CTA only for Apple subscriptions.
enum ProSourceKind {
    case apple
    case stripe
    case license
    case gift
    case flowPoints
    case admin
    case other(String)

    init(rawSource: String?) {
        switch rawSource {
        case "apple":         self = .apple
        case "stripe":        self = .stripe
        case "license":       self = .license
        case "gift_code":     self = .gift
        case "flow_points":   self = .flowPoints
        case "admin":         self = .admin
        case let s?:          self = .other(s)
        case nil:             self = .apple  // unknown — default to Apple CTAs
        }
    }

    var isApple: Bool {
        if case .apple = self { return true }
        return false
    }

    /// Human-readable source label used in the "already Pro" banner.
    var displayName: String {
        switch self {
        case .apple:       return "Apple subscription"
        case .stripe:      return "web subscription"
        case .license:     return "license"
        case .gift:        return "gift"
        case .flowPoints:  return "Flow Points"
        case .admin:       return "admin grant"
        case .other:       return "subscription"
        }
    }
}
