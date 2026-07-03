import Foundation
import Models
import Networking

/// Production ``SocialRepository`` that fetches from the ChapterFlow REST API.
///
/// This is an `actor` so its internal state is safely isolated;
/// the heavy lifting is async URLSession calls inside `APIClient`.
public actor LiveSocialRepository: SocialRepository {

    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
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
}
