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

    // MARK: - Gifts

    /// Fetches a gift by code for preview — shows type, sender, and expiry
    /// before the user commits to claiming.
    ///
    /// Maps to `GET /book/me/gifts/{code}`.
    /// Throws `AppError.notFound` when the code does not exist.
    func getGift(code: String) async throws -> Gift

    /// Claims a gift code, activating the entitlement server-side.
    ///
    /// Maps to `POST /book/me/gifts/{code}/claim`.
    /// After a successful claim, re-fetch entitlements — never grant Pro client-side.
    func claimGift(code: String) async throws -> GiftClaimResult

    /// Creates a new shareable gift code.
    ///
    /// Maps to `POST /book/me/gifts`.
    /// - Parameter giftType: The product to gift (e.g. `"pro_week"`).
    func createGift(giftType: String) async throws -> Gift

    // MARK: - Share events

    /// Logs a share event to the server after the user shares a card.
    ///
    /// Maps to `POST /book/me/share-events`. Fire-and-forget: the caller should
    /// not surface a failure to the user (a dropped analytics event is not fatal).
    func postShareEvent(cardType: ShareCardType, destination: ShareEventDestination) async throws

    // MARK: - Reflections

    /// Fetches the server's reflection history for a chapter.
    ///
    /// Maps to `GET /book/me/reflections/{bookId}/{n}`.
    /// May throw ``AppError/offline`` when the network is unavailable.
    func getReflections(bookId: String, chapterN: Int) async throws -> [ChapterReflection]

    /// Returns locally-queued reflections that have not yet been synced to the server.
    ///
    /// Never throws; reads the local outbox only.
    func getPendingReflections(bookId: String, chapterN: Int) async -> [PendingReflectionItem]

    /// Writes a new reflection.
    ///
    /// The item is persisted to the local outbox immediately, then the
    /// implementation attempts a network upload. If the upload succeeds the
    /// returned item has `syncState == .synced`; if offline it has `.pending`
    /// and will be retried by ``syncPendingReflections(bookId:chapterN:)``.
    /// Never throws — failures result in a `.pending` item.
    func postReflection(bookId: String, chapterN: Int, text: String) async -> PendingReflectionItem

    /// Requests AI feedback for a synced server reflection.
    ///
    /// Maps to `POST /book/me/reflections/{bookId}/{n}/feedback`.
    /// Returns the feedback text on success.
    func requestFeedback(
        bookId: String,
        chapterN: Int,
        serverReflectionId: String
    ) async throws -> String

    /// Marks a locally-pending reflection as wanting AI feedback.
    ///
    /// The feedback request is stored in the outbox and sent automatically once
    /// the reflection itself is successfully synced to the server.
    /// Returns the updated `PendingReflectionItem`, or `nil` if `localId` is unknown.
    func queueFeedbackForPending(localId: String) async -> PendingReflectionItem?

    /// Retries syncing all pending reflections for a chapter to the server.
    ///
    /// For each newly-synced item whose `feedbackState == .pending`, also fetches
    /// AI feedback automatically. Returns the up-to-date pending list after
    /// processing. Never throws; individual failures are logged and left for retry.
    func syncPendingReflections(bookId: String, chapterN: Int) async -> [PendingReflectionItem]

    // MARK: - Safety (P7.7)

    /// Blocks `userId`, preventing them from pairing, nudging, or viewing your profile.
    ///
    /// Maps to `POST /book/me/blocks`.
    /// ⚠️ Backend TODO: endpoint not yet implemented — see `Endpoint+Safety.swift`.
    func blockUser(userId: String) async throws

    /// Removes a block previously placed on `userId`.
    ///
    /// Maps to `DELETE /book/me/blocks/{userId}`.
    /// ⚠️ Backend TODO: endpoint not yet implemented — see `Endpoint+Safety.swift`.
    func unblockUser(userId: String) async throws

    /// Returns `true` if the current user has `userId` in their block list.
    ///
    /// Uses the locally-cached block list for speed; call ``refreshBlockedUsers()``
    /// to sync with the server first.
    func isBlocked(userId: String) async -> Bool

    /// Fetches the complete blocked-user list and refreshes the local cache.
    ///
    /// Maps to `GET /book/me/blocks`.
    /// ⚠️ Backend TODO: endpoint not yet implemented — see `Endpoint+Safety.swift`.
    func refreshBlockedUsers() async throws -> [BlockedUser]

    /// Submits a moderation report for a user or piece of content.
    ///
    /// At least one of `targetUserId` / `contentId` must be non-nil.
    /// Maps to `POST /book/moderation/reports`.
    /// ⚠️ Backend TODO: endpoint not yet implemented — see `Endpoint+Safety.swift`.
    func submitReport(
        targetUserId: String?,
        contentId: String?,
        contentType: String?,
        reason: ReportReason,
        details: String?
    ) async throws -> ReportResponse
}
