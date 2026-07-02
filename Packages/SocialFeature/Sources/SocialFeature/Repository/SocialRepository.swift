import Models

/// The single async data-layer contract for all of Lane S — profile, pairs,
/// gifts, reflections, share cards, and referrals.
///
/// Concrete implementations:
/// - ``LiveSocialRepository`` — production, network-backed.
/// - ``FakeSocialRepository`` — in-memory, for tests and previews.
///
/// Subsequent P7.x tasks add new methods to this protocol; every implementation
/// (Live + Fake) must be updated in the same PR.
public protocol SocialRepository: Sendable {

    // MARK: - Own profile

    /// Fetches the authenticated user's full profile including engagement stats.
    func getMyProfile() async throws -> OwnProfile

    /// Fetches all badges earned by the authenticated user.
    func getMyBadges() async throws -> [BadgeItem]

    /// Persists editable profile fields and returns the refreshed profile.
    ///
    /// Maps to `PATCH /book/me/settings`. Re-fetches the canonical profile
    /// immediately after to return consistent state.
    func updateSettings(_ body: UpdateSettingsBody) async throws -> OwnProfile

    // MARK: - Public / partner profiles

    /// Fetches another user's public (read-only) profile.
    ///
    /// Maps to `GET /book/users/{userId}/profile`.
    func getPublicProfile(userId: String) async throws -> PublicProfile
}
