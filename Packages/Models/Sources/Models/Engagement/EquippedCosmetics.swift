/// The cosmetics currently equipped by the user.
///
/// Updated by `POST /book/me/flow-points/redeem` with `action: "equip"`.
/// Stored in the `EngagementRepository` so Profile and Reader can read it
/// to apply themes and frames.
public struct EquippedCosmetics: Codable, Sendable, Equatable {
    /// The ID of the currently active theme cosmetic, or `nil` for the default.
    public let themeId: String?
    /// The ID of the currently active profile-frame cosmetic, or `nil` for none.
    public let frameId: String?

    public init(themeId: String?, frameId: String?) {
        self.themeId = themeId
        self.frameId = frameId
    }

    /// Sentinel value representing no cosmetics equipped.
    public static let none = EquippedCosmetics(themeId: nil, frameId: nil)
}
