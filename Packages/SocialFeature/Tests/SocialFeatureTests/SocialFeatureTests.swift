import Testing
import Foundation
import Models
import CoreKit
import Networking
@testable import SocialFeature

// MARK: - CosmeticItem tolerant-decoding evolution tests

@Suite("CosmeticItem")
struct CosmeticItemTests {

    @Test("known item types decode correctly")
    func knownTypes() throws {
        let json = """
        {"itemId":"f1","name":"Gold Wave","itemType":"avatar_frame"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(CosmeticItem.self, from: json)
        #expect(item.itemType == .avatarFrame)
    }

    @Test("unknown item type decodes to .unknown — never crashes")
    func unknownTypeToleratedDecoding() throws {
        let json = """
        {"itemId":"x1","name":"Future Frame","itemType":"holographic_ring"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(CosmeticItem.self, from: json)
        if case .unknown(let raw) = item.itemType {
            #expect(raw == "holographic_ring")
        } else {
            Issue.record("Expected .unknown but got \(item.itemType)")
        }
    }

    @Test("profile_theme and reader_theme decode correctly")
    func themeTypes() throws {
        let profileThemeJSON = """
        {"itemId":"t1","name":"Midnight","itemType":"profile_theme"}
        """.data(using: .utf8)!
        let readerThemeJSON = """
        {"itemId":"t2","name":"Sepia","itemType":"reader_theme"}
        """.data(using: .utf8)!
        let profileTheme = try JSONDecoder().decode(CosmeticItem.self, from: profileThemeJSON)
        let readerTheme = try JSONDecoder().decode(CosmeticItem.self, from: readerThemeJSON)
        #expect(profileTheme.itemType == .profileTheme)
        #expect(readerTheme.itemType == .readerTheme)
    }
}

// MARK: - ProfileTier tolerant-decoding evolution tests

@Suite("ProfileTier")
struct ProfileTierTests {

    @Test("all known tiers decode")
    func knownTiers() throws {
        let cases: [(String, ProfileTier)] = [
            ("reader", .reader), ("analyst", .analyst),
            ("synthesizer", .synthesizer), ("polymath", .polymath), ("luminary", .luminary),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ProfileTier.self, from: json)
            #expect(decoded == expected, "Failed for raw value '\(raw)'")
        }
    }

    @Test("unknown tier decodes to .unknown — never crashes")
    func unknownTierTolerated() throws {
        let json = "\"transcendent\"".data(using: .utf8)!
        let tier = try JSONDecoder().decode(ProfileTier.self, from: json)
        if case .unknown(let raw) = tier {
            #expect(raw == "transcendent")
        } else {
            Issue.record("Expected .unknown but got \(tier)")
        }
    }

    @Test("unknown tier displayLabel falls back to 'Reader'")
    func unknownTierDisplayLabel() {
        let tier = ProfileTier.unknown("galactic")
        #expect(tier.displayLabel == "Reader")
    }

    @Test("case-insensitive decoding")
    func caseInsensitive() throws {
        let json = "\"ANALYST\"".data(using: .utf8)!
        let tier = try JSONDecoder().decode(ProfileTier.self, from: json)
        #expect(tier == .analyst)
    }
}

// MARK: - OwnProfile computed properties

@Suite("OwnProfile")
struct OwnProfileTests {

    @Test("initials from two-word display name")
    func initialsFromTwoWords() {
        let profile = OwnProfile(
            userId: "u1", displayName: "Alice Reader",
            avatarUrl: nil, avatarEmoji: nil,
            tier: .analyst, tierProgress: 0.5,
            currentStreak: 7, longestStreak: 10,
            booksFinished: 3, flowPoints: 100,
            equippedFrame: nil, equippedTheme: nil,
            badgeCount: 2, joinedAt: nil
        )
        #expect(profile.initials == "AR")
    }

    @Test("initials from single-word display name")
    func initialsFromSingleWord() {
        let profile = OwnProfile(
            userId: "u2", displayName: "Alice",
            avatarUrl: nil, avatarEmoji: nil,
            tier: .reader, tierProgress: nil,
            currentStreak: 0, longestStreak: 0,
            booksFinished: 0, flowPoints: 0,
            equippedFrame: nil, equippedTheme: nil,
            badgeCount: 0, joinedAt: nil
        )
        #expect(profile.initials == "A")
    }

    @Test("initials fallback when displayName is nil")
    func initialsNilDisplayName() {
        let profile = OwnProfile(
            userId: "u3", displayName: nil,
            avatarUrl: nil, avatarEmoji: nil,
            tier: .reader, tierProgress: nil,
            currentStreak: 0, longestStreak: 0,
            booksFinished: 0, flowPoints: 0,
            equippedFrame: nil, equippedTheme: nil,
            badgeCount: 0, joinedAt: nil
        )
        #expect(profile.initials == "?")
    }

    @Test("OwnProfileResponse decodes envelope correctly")
    func profileResponseEnvelope() throws {
        let json = """
        {
          "profile": {
            "userId": "user-123", "displayName": "Alice",
            "avatarUrl": null, "avatarEmoji": "📚",
            "tier": "analyst", "tierProgress": 0.65,
            "currentStreak": 14, "longestStreak": 21,
            "booksFinished": 7, "flowPoints": 4200,
            "equippedFrame": null, "equippedTheme": null,
            "badgeCount": 5, "joinedAt": "2024-01-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(OwnProfileResponse.self, from: json)
        #expect(response.profile.userId == "user-123")
        #expect(response.profile.tier == .analyst)
        #expect(response.profile.currentStreak == 14)
    }

    @Test("OwnProfileResponse tolerates unknown tier in nested profile")
    func profileResponseToleratesUnknownTier() throws {
        let json = """
        {
          "profile": {
            "userId": "user-xyz", "displayName": "Future User",
            "tier": "transcendent", "currentStreak": 0, "longestStreak": 0,
            "booksFinished": 0, "flowPoints": 0, "badgeCount": 0
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(OwnProfileResponse.self, from: json)
        if case .unknown(let raw) = response.profile.tier {
            #expect(raw == "transcendent")
        } else {
            Issue.record("Expected .unknown tier")
        }
    }
}

// MARK: - PublicProfile tests

@Suite("PublicProfile")
struct PublicProfileTests {

    @Test("PublicProfileResponse decodes envelope")
    func publicProfileResponseEnvelope() throws {
        let json = """
        {
          "profile": {
            "userId": "partner-001", "displayName": "Bob",
            "tier": "synthesizer", "currentStreak": 5,
            "booksFinished": 12, "badgeCount": 4
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: json)
        #expect(response.profile.userId == "partner-001")
        #expect(response.profile.tier == .synthesizer)
        #expect(response.profile.booksFinished == 12)
    }

    @Test("public profile with equipped cosmetics decodes tolerantly")
    func publicProfileWithCosmetics() throws {
        let json = """
        {
          "profile": {
            "userId": "partner-002", "displayName": "Carol",
            "tier": "luminary", "currentStreak": 100,
            "booksFinished": 40, "badgeCount": 30,
            "equippedFrame": {
              "itemId": "frame-stellar", "name": "Stellar",
              "itemType": "avatar_frame", "rarity": "legendary"
            },
            "equippedTheme": null
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: json)
        #expect(response.profile.equippedFrame?.itemId == "frame-stellar")
        #expect(response.profile.equippedFrame?.itemType == .avatarFrame)
        #expect(response.profile.equippedTheme == nil)
    }
}

// MARK: - FakeSocialRepository tests (profile methods)

@Suite("FakeSocialRepository")
struct FakeSocialRepositoryTests {

    @Test("getMyProfile returns seeded profile")
    func getMyProfileReturnsSeeded() async throws {
        let repo = FakeSocialRepository(profile: .preview)
        let profile = try await repo.getMyProfile()
        #expect(profile.userId == OwnProfile.preview.userId)
    }

    @Test("updateSettings mutates the display name")
    func updateSettingsMutatesDisplayName() async throws {
        let repo = FakeSocialRepository(profile: .preview)
        let updated = try await repo.updateSettings(UpdateSettingsBody(displayName: "New Name"))
        #expect(updated.displayName == "New Name")
        let refetched = try await repo.getMyProfile()
        #expect(refetched.displayName == "New Name")
    }

    @Test("recordedUpdates tracks every call to updateSettings")
    func recordedUpdatesTracked() async throws {
        let repo = FakeSocialRepository(profile: .preview)
        _ = try await repo.updateSettings(UpdateSettingsBody(displayName: "A"))
        _ = try await repo.updateSettings(UpdateSettingsBody(displayName: "B"))
        let recorded = await repo.recordedUpdates
        #expect(recorded.count == 2)
        #expect(recorded[0].displayName == "A")
        #expect(recorded[1].displayName == "B")
    }

    @Test("forced error propagates from profile methods")
    func forcedErrorPropagatesProfileMethods() async {
        let repo = FakeSocialRepository(error: .offline)
        var caughtCount = 0
        do { _ = try await repo.getMyProfile() } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.getMyBadges() } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.updateSettings(UpdateSettingsBody()) } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.getPublicProfile(userId: "any") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        #expect(caughtCount == 4)
    }

    @Test("forced error propagates from pairs methods")
    func forcedErrorPropagatesPairMethods() async {
        let repo = FakeSocialRepository(error: .offline)
        var caughtCount = 0
        do { _ = try await repo.getPairs() } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.createInvite() } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.acceptInvite(code: "X") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.getPair(partnerId: "any") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { try await repo.deletePair(partnerId: "any") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { try await repo.nudgePartner(partnerId: "any") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        #expect(caughtCount == 6)
    }

    @Test("getPublicProfile returns seeded partner profile")
    func getPublicProfileReturnsSeeded() async throws {
        let partner = PublicProfile.preview(userId: "partner-abc")
        let repo = FakeSocialRepository(publicProfiles: ["partner-abc": partner])
        let fetched = try await repo.getPublicProfile(userId: "partner-abc")
        #expect(fetched.userId == "partner-abc")
    }

    @Test("getPublicProfile returns default preview for unknown userId")
    func getPublicProfileDefaultPreview() async throws {
        let repo = FakeSocialRepository()
        let fetched = try await repo.getPublicProfile(userId: "unknown-user")
        #expect(!fetched.userId.isEmpty)
    }

    @Test("getPairs returns seeded pairs")
    func getPairsReturnsSeeded() async throws {
        let repo = FakeSocialRepository(pairs: [.previewActive, .previewPending])
        let fetched = try await repo.getPairs()
        #expect(fetched.count == 2)
        #expect(fetched[0].status == .active)
        #expect(fetched[1].status == .pending)
    }

    @Test("acceptInvite adds the accepted pair to the list")
    func acceptInviteAddsPair() async throws {
        let repo = FakeSocialRepository()
        let pair = try await repo.acceptInvite(code: "TEST-CODE")
        #expect(pair.partnerId == "accepted-TEST-CODE")
        let pairs = try await repo.getPairs()
        #expect(pairs.contains { $0.partnerId == "accepted-TEST-CODE" })
    }

    @Test("deletePair removes the pair and records the delete")
    func deletePairRemovesPair() async throws {
        let repo = FakeSocialRepository(pairs: [.previewActive])
        try await repo.deletePair(partnerId: ReadingPair.previewActive.partnerId)
        let remaining = try await repo.getPairs()
        #expect(remaining.isEmpty)
        let recorded = await repo.recordedDeletes
        #expect(recorded.contains(ReadingPair.previewActive.partnerId))
    }

    @Test("nudgePartner records the nudge")
    func nudgePartnerRecordsNudge() async throws {
        let repo = FakeSocialRepository()
        try await repo.nudgePartner(partnerId: "user-bob")
        let recorded = await repo.recordedNudges
        #expect(recorded.contains("user-bob"))
    }
}

// MARK: - Social endpoint tests

@Suite("SocialEndpoints")
struct SocialEndpointsTests {

    @Test("getMyProfile builds correct path")
    func getMyProfilePath() {
        let endpoint = Endpoints.getMyProfile()
        #expect(endpoint.path == "/book/me/profile")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth)
    }

    @Test("getPublicProfile builds correct path with userId")
    func getPublicProfilePath() {
        let endpoint = Endpoints.getPublicProfile(userId: "abc123")
        #expect(endpoint.path == "/book/users/abc123/profile")
        #expect(endpoint.requiresAuth)
    }

    @Test("updateSettings builds PATCH with body")
    func updateSettingsEndpoint() throws {
        struct Body: Encodable { let displayName: String }
        let endpoint = try Endpoints.updateSettings(Body(displayName: "Alice"))
        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "/book/me/settings")
        #expect(endpoint.httpBody != nil)
        #expect(endpoint.requiresAuth)
    }

    @Test("getPairs builds GET /book/me/pairs")
    func getPairsEndpoint() {
        let endpoint = Endpoints.getPairs()
        #expect(endpoint.path == "/book/me/pairs")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth)
    }

    @Test("createPairInvite builds POST /book/me/pairs/invite")
    func createPairInviteEndpoint() throws {
        let endpoint = try Endpoints.createPairInvite()
        #expect(endpoint.path == "/book/me/pairs/invite")
        #expect(endpoint.method == .post)
        #expect(endpoint.requiresAuth)
    }

    @Test("acceptPairInvite builds POST with code in path")
    func acceptPairInviteEndpoint() throws {
        let endpoint = try Endpoints.acceptPairInvite(code: "ABCD-1234")
        #expect(endpoint.path == "/book/me/pairs/accept/ABCD-1234")
        #expect(endpoint.method == .post)
    }

    @Test("getPair builds GET with partnerId in path")
    func getPairEndpoint() {
        let endpoint = Endpoints.getPair(partnerId: "user-bob")
        #expect(endpoint.path == "/book/me/pairs/user-bob")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth)
    }

    @Test("deletePair builds DELETE with partnerId in path")
    func deletePairEndpoint() {
        let endpoint = Endpoints.deletePair(partnerId: "user-bob")
        #expect(endpoint.path == "/book/me/pairs/user-bob")
        #expect(endpoint.method == .delete)
        #expect(endpoint.requiresAuth)
    }

    @Test("nudgePartner builds POST /pairs/{id}/nudge")
    func nudgePartnerEndpoint() throws {
        let endpoint = try Endpoints.nudgePartner(partnerId: "user-bob")
        #expect(endpoint.path == "/book/me/pairs/user-bob/nudge")
        #expect(endpoint.method == .post)
    }
}
