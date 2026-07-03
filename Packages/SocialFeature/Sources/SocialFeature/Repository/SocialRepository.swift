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

    // MARK: - Reading pairs

    /// Returns all active and pending reading pairs for the authenticated user.
    ///
    /// Maps to `GET /book/me/pairs`.
    func getPairs() async throws -> [ReadingPair]

    /// Creates a new invite and returns its code + shareable Universal Link.
    ///
    /// Maps to `POST /book/me/pairs/invite`.
    func createInvite() async throws -> PairInvite

    /// Accepts a reading-pair invite by code.
    ///
    /// Maps to `POST /book/me/pairs/accept/{code}`.
    /// - Returns: The newly created `ReadingPair`.
    /// - Throws: `.notFound` for an unknown code, `.server` for expired codes.
    func acceptInvite(code: String) async throws -> ReadingPair

    /// Fetches a single pair by the partner's user ID.
    ///
    /// Maps to `GET /book/me/pairs/{partnerId}`.
    func getPair(partnerId: String) async throws -> ReadingPair

    /// Ends the reading partnership with the given partner (server-side delete).
    ///
    /// Maps to `DELETE /book/me/pairs/{partnerId}`.
    func deletePair(partnerId: String) async throws

    /// Sends a nudge notification to the partner.
    ///
    /// Maps to `POST /book/me/pairs/{partnerId}/nudge`.
    /// - Throws: `.rateLimited` when the server enforces a cooldown.
    func nudgePartner(partnerId: String) async throws
}
