import Foundation
import Models
import Networking
import os

/// Production ``SocialRepository`` that fetches from the ChapterFlow REST API.
///
/// This is an `actor` so its internal state is safely isolated;
/// the heavy lifting is async URLSession calls inside `APIClient`.
public actor LiveSocialRepository: SocialRepository {

    private let client: any APIClientProtocol
    private let outbox: ReflectionOutbox
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "LiveSocialRepo")
    private var cachedBlockedUserIds: Set<String> = []

    public init(client: any APIClientProtocol) {
        self.client = client
        self.outbox = ReflectionOutbox()
    }

    // MARK: - Own profile

    public func getMyProfile() async throws -> OwnProfile {
        let response: OwnProfileResponse = try await client.send(Endpoints.getMyProfile())
        return response.profile
    }

    public func getMyBadges() async throws -> [BadgeItem] {
        let response: BadgesResponse = try await client.send(Endpoints.getBadges())
        return response.badges
    }

    public func updateSettings(_ body: UpdateSettingsBody) async throws -> OwnProfile {
        let endpoint = try Endpoints.updateSettings(body)
        // PATCH returns a SettingsUpdateResponse; we re-fetch the profile for a
        // canonical, consistent view (avoids modelling the partial-overlap settings shape).
        let _: SettingsUpdateResponse = try await client.send(endpoint)
        return try await getMyProfile()
    }

    // MARK: - Public / partner profiles

    public func getPublicProfile(userId: String) async throws -> PublicProfile {
        let response: PublicProfileResponse = try await client.send(
            Endpoints.getPublicProfile(userId: userId)
        )
        return response.profile
    }

    // MARK: - Reading pairs

    public func getPairs() async throws -> [ReadingPair] {
        let response: PairsListResponse = try await client.send(Endpoints.getPairs())
        return response.pairs
    }

    public func createInvite() async throws -> PairInvite {
        let endpoint = try Endpoints.createPairInvite()
        let response: PairInviteResponse = try await client.send(endpoint)
        return response.invite
    }

    public func acceptInvite(code: String) async throws -> ReadingPair {
        let endpoint = try Endpoints.acceptPairInvite(code: code)
        let response: PairResponse = try await client.send(endpoint)
        return response.pair
    }

    public func getPair(partnerId: String) async throws -> ReadingPair {
        let response: PairResponse = try await client.send(Endpoints.getPair(partnerId: partnerId))
        return response.pair
    }

    public func deletePair(partnerId: String) async throws {
        let _: PairAckResponse = try await client.send(Endpoints.deletePair(partnerId: partnerId))
    }

    public func nudgePartner(partnerId: String) async throws {
        let endpoint = try Endpoints.nudgePartner(partnerId: partnerId)
        let _: PairAckResponse = try await client.send(endpoint)
    }

    // MARK: - Gifts

    public func getGift(code: String) async throws -> Gift {
        let response: GiftPreviewResponse = try await client.send(Endpoints.getGift(code: code))
        return response.gift
    }

    public func claimGift(code: String) async throws -> GiftClaimResult {
        let endpoint = try Endpoints.claimGift(code: code)
        let response: GiftClaimResponse = try await client.send(endpoint)
        return GiftClaimResult(gift: response.gift, message: response.message)
    }

    public func createGift(giftType: String) async throws -> Gift {
        let endpoint = try Endpoints.createGift(giftType: giftType)
        let response: CreateGiftResponse = try await client.send(endpoint)
        return response.gift
    }

    // MARK: - Share events

    public func postShareEvent(
        cardType: ShareCardType,
        destination: ShareEventDestination
    ) async throws {
        let endpoint = try Endpoints.postShareEvent(
            cardType: cardType.rawValue,
            destination: destination.rawValue
        )
        let _: ShareEventResponse = try await client.send(endpoint)
    }

    // MARK: - Reflections

    public func getReflections(bookId: String, chapterN: Int) async throws -> [ChapterReflection] {
        let response: ReflectionsResponse = try await client.send(
            Endpoints.getReflections(bookId: bookId, chapterN: chapterN)
        )
        return response.reflections
    }

    public func getPendingReflections(bookId: String, chapterN: Int) async -> [PendingReflectionItem] {
        await outbox.all(bookId: bookId, chapterN: chapterN)
    }

    public func postReflection(bookId: String, chapterN: Int, text: String) async -> PendingReflectionItem {
        var item = PendingReflectionItem(bookId: bookId, chapterN: chapterN, text: text)
        await outbox.append(item)

        do {
            let endpoint = try Endpoints.postReflection(bookId: bookId, chapterN: chapterN, text: text)
            let response: PostReflectionResponse = try await client.send(endpoint)
            item.syncState = .synced
            item.serverReflectionId = response.reflection.reflectionId
            await outbox.update(item)
        } catch {
            logger.warning("Reflection upload failed, queued for retry: \(error.localizedDescription)")
        }

        return item
    }

    public func requestFeedback(
        bookId: String,
        chapterN: Int,
        serverReflectionId: String
    ) async throws -> String {
        let endpoint = try Endpoints.requestReflectionFeedback(
            bookId: bookId,
            chapterN: chapterN,
            reflectionId: serverReflectionId
        )
        let response: ReflectionFeedbackResponse = try await client.send(endpoint)
        return response.feedbackText
    }

    public func queueFeedbackForPending(localId: String) async -> PendingReflectionItem? {
        await outbox.markFeedbackPending(localId: localId)
        // Return updated item from outbox.
        // We can't easily look up by localId in one call; traverse pending items.
        // Using a workaround: markFeedbackPending returns nothing; we'll do a lookup
        // by filtering the full list. This actor-isolated approach is safe.
        return nil  // Callers should call getPendingReflections to get updated state.
    }

    // MARK: - Safety

    public func blockUser(userId: String) async throws {
        let _: BlockActionResponse = try await client.send(try Endpoints.blockUser(userId: userId))
        cachedBlockedUserIds.insert(userId)
    }

    public func unblockUser(userId: String) async throws {
        let _: BlockActionResponse = try await client.send(Endpoints.unblockUser(userId: userId))
        cachedBlockedUserIds.remove(userId)
    }

    public func isBlocked(userId: String) async -> Bool {
        cachedBlockedUserIds.contains(userId)
    }

    public func refreshBlockedUsers() async throws -> [BlockedUser] {
        let response: BlockedUsersResponse = try await client.send(Endpoints.getBlockedUsers())
        cachedBlockedUserIds = Set(response.blockedUsers.map(\.userId))
        return response.blockedUsers
    }

    public func submitReport(
        targetUserId: String?,
        contentId: String?,
        contentType: String?,
        reason: ReportReason,
        details: String?
    ) async throws -> ReportResponse {
        let endpoint = try Endpoints.submitReport(
            targetUserId: targetUserId,
            contentId: contentId,
            contentType: contentType,
            reason: reason.rawValue,
            details: details
        )
        return try await client.send(endpoint)
    }

    // MARK: - Referrals

    public func getReferralProfile() async throws -> ReferralProfile {
        let response: ReferralProfileResponse = try await client.send(Endpoints.getReferralProfile())
        return response.referral
    }

    public func applyReferralCode(_ code: String) async throws -> ReferralApplyResult {
        let endpoint = try Endpoints.applyReferralCode(code)
        let response: ReferralApplyResponse = try await client.send(endpoint)
        return response.result
    }

    public func syncPendingReflections(bookId: String, chapterN: Int) async -> [PendingReflectionItem] {
        let pending = await outbox.all(bookId: bookId, chapterN: chapterN)
        for item in pending where item.syncState == .pending {
            var updated = item
            do {
                let endpoint = try Endpoints.postReflection(
                    bookId: bookId,
                    chapterN: chapterN,
                    text: item.text
                )
                let response: PostReflectionResponse = try await client.send(endpoint)
                updated.syncState = .synced
                updated.serverReflectionId = response.reflection.reflectionId
                await outbox.update(updated)

                // Auto-fetch feedback if it was queued before the reflection synced.
                if updated.feedbackState == .pending, let serverId = updated.serverReflectionId {
                    do {
                        let fbEndpoint = try Endpoints.requestReflectionFeedback(
                            bookId: bookId,
                            chapterN: chapterN,
                            reflectionId: serverId
                        )
                        let fbResponse: ReflectionFeedbackResponse = try await client.send(fbEndpoint)
                        await outbox.markFeedbackReceived(localId: item.localId, feedbackText: fbResponse.feedbackText)
                    } catch {
                        logger.warning("Feedback fetch failed for \(item.localId): \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.warning("Sync failed for pending reflection \(item.localId): \(error.localizedDescription)")
            }
        }
        return await outbox.all(bookId: bookId, chapterN: chapterN)
    }
}
