/// The user's subscription entitlement state.
///
/// Part of the response from `GET /book/me/entitlements`.
/// Use `EntitlementEvaluator` to answer gating questions from this value.
public struct Entitlement: Codable, Sendable {

    /// The subscription tier.
    ///
    /// Server-evolution contract: unrecognised raw values decode to `.unknown(rawValue)`
    /// instead of throwing. Views should treat `.unknown` the same as `.free`.
    public enum Plan: Sendable, Equatable, Hashable {
        case free
        case pro
        /// A plan the client does not recognise. Treat as `.free`; never crash.
        case unknown(String)
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

    public init(
        plan: Plan,
        proStatus: String?,
        proSource: String?,
        freeBookSlots: Int,
        unlockedBookIds: [String],
        unlockedBooksCount: Int,
        remainingFreeStarts: Int,
        currentPeriodEnd: String?,
        cancelAtPeriodEnd: Bool?,
        licenseKey: String?,
        licenseExpiresAt: String?
    ) {
        self.plan = plan
        self.proStatus = proStatus
        self.proSource = proSource
        self.freeBookSlots = freeBookSlots
        self.unlockedBookIds = unlockedBookIds
        self.unlockedBooksCount = unlockedBooksCount
        self.remainingFreeStarts = remainingFreeStarts
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.licenseKey = licenseKey
        self.licenseExpiresAt = licenseExpiresAt
    }
}

// MARK: - Plan RawRepresentable + Codable

extension Entitlement.Plan: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .free:           return "FREE"
        case .pro:            return "PRO"
        case .unknown(let s): return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "FREE": self = .free
        case "PRO":  self = .pro
        default:     self = .unknown(rawValue)
        }
    }
}

extension Entitlement.Plan: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Entitlement.Plan(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
