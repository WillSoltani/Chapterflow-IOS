import Testing
import Foundation
import Models
@testable import SocialFeature

// MARK: - Deployed-shape contract tests (social endpoints)
//
// Shapes derived from the DEPLOYED server code at production sha 19b44fac.
// Provenance per suite. See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.chapterFlow.decode(T.self, from: Data(json.utf8))
}

// Provenance: app/app/api/book/me/profile/route.ts:280-292 + _lib/identity.ts:5-15.
@Suite("Deployed shape — GET /book/me/profile (SocialFeature)")
struct DeployedProfileTests {

    @Test("null profile + identity synthesizes an OwnProfile from identity.sub")
    func nullProfileSynthesis() throws {
        let payload = #"""
        {"profile":null,
         "identity":{"sub":"user-123","email":"a@b.c","emailVerified":true,
           "displayName":"Will","authDisplayName":"Will","profileDisplayName":null,
           "givenName":"Will","familyName":null,"preferredUsername":null,
           "source":"cognito"},
         "inferredLocation":null,"updatedAt":null}
        """#
        let response = try decode(OwnProfileResponse.self, payload)
        #expect(response.profile.userId == "user-123")
        #expect(response.profile.displayName == "Will")
        #expect(response.profile.tier == .reader)   // default; overlaid by tier endpoint
        #expect(response.profile.flowPoints == 0)   // default; overlaid by points endpoint
    }

    @Test("profile settings override the identity display name")
    func settingsNameWins() throws {
        let payload = #"""
        {"profile":{"displayName":"Reader Will","avatarEmoji":"📚"},
         "identity":{"sub":"user-123","email":null,"emailVerified":false,
           "displayName":"Will","authDisplayName":null,"profileDisplayName":"Reader Will",
           "givenName":null,"familyName":null,"preferredUsername":null,
           "source":"profile"},
         "inferredLocation":null,"updatedAt":"2026-07-09T10:00:00Z"}
        """#
        let response = try decode(OwnProfileResponse.self, payload)
        #expect(response.profile.displayName == "Reader Will")
        #expect(response.profile.avatarEmoji == "📚")
    }

    @Test("the canonical {profile:{userId,…}} shape still decodes")
    func canonicalStillDecodes() throws {
        let payload = #"""
        {"profile":{"userId":"u1","displayName":"W","avatarUrl":null,"avatarEmoji":null,
          "tier":"analyst","tierProgress":0.5,"currentStreak":3,"longestStreak":9,
          "booksFinished":4,"flowPoints":120,"equippedFrame":null,"equippedTheme":null,
          "badgeCount":7,"joinedAt":"2026-06-01T00:00:00Z"}}
        """#
        let response = try decode(OwnProfileResponse.self, payload)
        #expect(response.profile.userId == "u1")
        #expect(response.profile.tier == .analyst)
        #expect(response.profile.booksFinished == 4)
    }
}

// Provenance: app/app/api/book/me/pairs/route.ts:10-21 + types.ts:1015-1023.
@Suite("Deployed shape — GET /book/me/pairs (SocialFeature)")
struct DeployedPairsTests {

    @Test("the single {pair, partner} shape becomes a one-element pairs list")
    func singlePairDecodes() throws {
        let payload = #"""
        {"pair":{"userId":"u1","partnerId":"u2","pairedAt":"2026-07-01T00:00:00Z",
          "status":"active","createdAt":"2026-07-01T00:00:00Z",
          "updatedAt":"2026-07-01T00:00:00Z"},
         "partner":{"displayName":"Ada"}}
        """#
        let response = try decode(PairsListResponse.self, payload)
        #expect(response.pairs.count == 1)
        let pair = try #require(response.pairs.first)
        #expect(pair.partnerId == "u2")
        #expect(pair.partnerDisplayName == "Ada") // merged from the partner summary
        #expect(pair.status == .active)
    }

    @Test("no active pair → empty list")
    func nullPairDecodes() throws {
        let response = try decode(PairsListResponse.self, #"{"pair":null,"partner":null}"#)
        #expect(response.pairs.isEmpty)
    }

    @Test("an 'ended' pair maps to .expired")
    func endedMapsToExpired() throws {
        let payload = #"""
        {"pair":{"userId":"u1","partnerId":"u2","pairedAt":"2026-07-01T00:00:00Z",
          "status":"ended","createdAt":"2026-07-01T00:00:00Z",
          "updatedAt":"2026-07-02T00:00:00Z"},
         "partner":null}
        """#
        let response = try decode(PairsListResponse.self, payload)
        #expect(response.pairs.first?.status == .expired)
    }

    @Test("the canonical {pairs:[…]} list still decodes")
    func canonicalListStillDecodes() throws {
        let payload = #"""
        {"pairs":[{"partnerId":"u9","partnerDisplayName":"Zoe","partnerAvatarUrl":null,
          "partnerAvatarEmoji":null,"partnerTier":"reader","partnerCurrentStreak":2,
          "partnerBooksFinished":1,"status":"active","pairedAt":null}]}
        """#
        let response = try decode(PairsListResponse.self, payload)
        #expect(response.pairs.count == 1)
        #expect(response.pairs.first?.partnerDisplayName == "Zoe")
    }
}

// SAFETY-CRITICAL (red-team finding): a blocked user must never appear
// unblocked because the blocklist decoded to empty over a key rename.
@Suite("Deployed shape — GET /book/me/blocks (SocialFeature)")
struct DeployedBlockedUsersTests {

    @Test("id-keyed blocked users still decode (house-style rename)")
    func idKeyedBlocklistDecodes() throws {
        let payload = #"""
        {"blockedUsers":[{"id":"u2","blockedAt":"2026-07-01T00:00:00Z"},
                         {"blockedUserId":"u3"}]}
        """#
        let response = try decode(BlockedUsersResponse.self, payload)
        #expect(response.blockedUsers.count == 2)
        #expect(response.blockedUsers.map(\.userId).sorted() == ["u2", "u3"])
    }

    @Test("canonical userId-keyed blocklist still decodes")
    func canonicalBlocklistDecodes() throws {
        let payload = #"{"blockedUsers":[{"userId":"u2","blockedAt":null}]}"#
        let response = try decode(BlockedUsersResponse.self, payload)
        #expect(response.blockedUsers.first?.userId == "u2")
    }
}
