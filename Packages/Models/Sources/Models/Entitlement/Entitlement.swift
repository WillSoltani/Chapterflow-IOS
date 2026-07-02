/// The user's subscription entitlement state.
///
/// Part of the response from `GET /book/me/entitlements`.
/// Use `EntitlementEvaluator` to answer gating questions from this value.
public struct Entitlement: Codable, Sendable {
    /// The subscription tier.
    public enum Plan: String, Codable, Sendable, Equatable {
        case free = "FREE"
        case pro = "PRO"
    }

    public let plan: Plan
    /// `"active"`, `"trialing"`, `"past_due"`, `"canceled"`, etc. `nil` for free users.
    public let proStatus: String?
    /// `"stripe"`, `"apple"`, `"license"`, `"flow_points"`, `"gift_code"`, `"admin"`. `nil` for free.
    public let proSource: String?
    public let freeBookSlots: Int
    public let unlockedBookIds: [String]
    public let unlockedBooksCount: Int
    public let remainingFreeStarts: Int
    public let currentPeriodEnd: String?
    public let cancelAtPeriodEnd: Bool?
    public let licenseKey: String?
    public let licenseExpiresAt: String?
}
