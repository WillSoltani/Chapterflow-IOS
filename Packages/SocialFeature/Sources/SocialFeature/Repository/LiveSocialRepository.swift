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
}
