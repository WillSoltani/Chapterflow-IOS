import Testing
import Foundation
import CoreKit
import Networking
@testable import SocialFeature

// MARK: - ReferralRewardKind tolerant-decoding tests

@Suite("ReferralRewardKind")
struct ReferralRewardKindTests {

    @Test("known kinds decode correctly")
    func knownKinds() throws {
        let cases: [(String, ReferralRewardKind)] = [
            ("extra_free_slot", .extraFreeSlot),
            ("streak_shield",   .streakShield),
            ("pro_week",        .proWeek),
            ("pro_month",       .proMonth),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ReferralRewardKind.self, from: json)
            #expect(decoded == expected, "Failed for raw '\(raw)'")
        }
    }

    @Test("unknown kind decodes to .unknown — never crashes")
    func unknownKindTolerated() throws {
        let json = "\"diamond_ticket\"".data(using: .utf8)!
        let kind = try JSONDecoder().decode(ReferralRewardKind.self, from: json)
        if case .unknown(let raw) = kind {
            #expect(raw == "diamond_ticket")
        } else {
            Issue.record("Expected .unknown but got \(kind)")
        }
    }

    @Test("unknown kind has sensible displayLabel — never crashes a view")
    func unknownKindDisplayLabel() {
        let kind = ReferralRewardKind.unknown("future_reward")
        #expect(kind.displayLabel == "Bonus Reward")
    }

    @Test("unknown kind has sensible systemImageName — never crashes a view")
    func unknownKindSystemImageName() {
        let kind = ReferralRewardKind.unknown("future_reward")
        #expect(!kind.systemImageName.isEmpty)
    }
}

// MARK: - ReferralProfile decoding tests

@Suite("ReferralProfile")
struct ReferralProfileTests {

    @Test("full response decodes correctly")
    func fullResponse() throws {
        let json = """
        {
          "referral": {
            "code": "ALICE42",
            "shareUrl": "https://app.chapterflow.ca/ref/ALICE42",
            "stats": { "pending": 3, "activated": 5, "pro": 2 },
            "rewards": [
              {
                "kind": "pro_week",
                "title": "7 Days of Pro",
                "description": "Earn when a friend signs up.",
                "earnedAt": "2024-02-01T10:00:00Z",
                "isEarned": true
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralProfileResponse.self, from: json)
        let profile = response.referral

        #expect(profile.code == "ALICE42")
        #expect(profile.shareUrl == "https://app.chapterflow.ca/ref/ALICE42")
        #expect(profile.stats.pending == 3)
        #expect(profile.stats.activated == 5)
        #expect(profile.stats.pro == 2)
        #expect(profile.rewards.count == 1)
        #expect(profile.rewards[0].isEarned == true)
        #expect(profile.rewards[0].kind == .proWeek)
    }

    @Test("missing shareUrl falls back to custom scheme URL")
    func missingShareUrlFallback() throws {
        let json = """
        {
          "referral": {
            "code": "BOB007",
            "stats": { "pending": 0, "activated": 0, "pro": 0 },
            "rewards": []
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralProfileResponse.self, from: json)
        let profile = response.referral

        #expect(profile.shareUrl == nil)
        let resolved = profile.resolvedShareURL
        #expect(resolved.absoluteString == "chapterflow://ref/BOB007")
    }

    @Test("rewards with unknown kind decode lossily — surviving elements intact")
    func rewardsLossyDecoding() throws {
        let json = """
        {
          "referral": {
            "code": "TEST01",
            "stats": { "pending": 0, "activated": 0, "pro": 0 },
            "rewards": [
              {
                "kind": "pro_week",
                "title": "Week of Pro",
                "description": "Good reward",
                "isEarned": true
              },
              null
            ]
          }
        }
        """.data(using: .utf8)!

        // Should not throw; the null element is dropped.
        let response = try JSONDecoder().decode(ReferralProfileResponse.self, from: json)
        #expect(response.referral.rewards.count == 1)
        #expect(response.referral.rewards[0].kind == .proWeek)
    }

    @Test("unknown reward kind in array survives — no crash")
    func unknownRewardKindInArray() throws {
        let json = """
        {
          "referral": {
            "code": "FUT01",
            "stats": { "pending": 1, "activated": 0, "pro": 0 },
            "rewards": [
              {
                "kind": "diamond_throne",
                "title": "Diamond Throne",
                "description": "Future reward",
                "isEarned": false
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralProfileResponse.self, from: json)
        let reward = try #require(response.referral.rewards.first)
        if case .unknown(let raw) = reward.kind {
            #expect(raw == "diamond_throne")
        } else {
            Issue.record("Expected .unknown reward kind")
        }
    }
}

// MARK: - ReferralApplyResult decoding tests

@Suite("ReferralApplyResult")
struct ReferralApplyResultTests {

    @Test("success result decodes correctly")
    func successDecodes() throws {
        let json = """
        { "result": { "success": true, "message": "Code applied!" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralApplyResponse.self, from: json)
        #expect(response.result.success == true)
        #expect(response.result.message == "Code applied!")
    }

    @Test("failure result decodes correctly")
    func failureDecodes() throws {
        let json = """
        { "result": { "success": false, "message": "Code already used." } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralApplyResponse.self, from: json)
        #expect(response.result.success == false)
        #expect(response.result.message == "Code already used.")
    }

    @Test("missing message field decodes to nil")
    func missingMessageDecodes() throws {
        let json = """
        { "result": { "success": true } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ReferralApplyResponse.self, from: json)
        #expect(response.result.success == true)
        #expect(response.result.message == nil)
    }
}

// MARK: - FakeSocialRepository referral tests

@Suite("FakeSocialRepository — Referrals")
struct FakeSocialRepositoryReferralTests {

    @Test("getReferralProfile returns preview data")
    func getReferralProfileReturnsPreview() async throws {
        let repo = FakeSocialRepository()
        let profile = try await repo.getReferralProfile()
        #expect(!profile.code.isEmpty)
    }

    @Test("applyReferralCode records the code and returns success")
    func applyCodeRecordsAndSucceeds() async throws {
        let repo = FakeSocialRepository()
        let result = try await repo.applyReferralCode("FRIEND99")
        #expect(result.success == true)
        let recorded = await repo.recordedAppliedCodes
        #expect(recorded == ["FRIEND99"])
    }

    @Test("applyReferralCode trims and upcases via ReferralModel before hitting repo")
    func referralModelTrimsCode() async {
        let repo = FakeSocialRepository()
        let model = await ReferralModel(repository: repo)
        await model.applyCode("  alice42  ")
        let recorded = await repo.recordedAppliedCodes
        // Model uppercases before sending to repo.
        #expect(recorded == ["ALICE42"])
    }

    @Test("forced error propagates from getReferralProfile")
    func forcedErrorPropagates() async {
        let repo = FakeSocialRepository(error: .offline)
        do {
            _ = try await repo.getReferralProfile()
            Issue.record("Expected error to be thrown")
        } catch let e as AppError {
            #expect(e.code == "offline")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("forced error propagates from applyReferralCode")
    func forcedErrorPropagatesFromApply() async {
        let repo = FakeSocialRepository(error: .offline)
        do {
            _ = try await repo.applyReferralCode("CODE")
            Issue.record("Expected error to be thrown")
        } catch let e as AppError {
            #expect(e.code == "offline")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - ReferralModel logic tests

@Suite("ReferralModel")
struct ReferralModelTests {

    @Test("empty code returns failure without hitting repo")
    func emptyCodeReturnsFailure() async {
        let repo = FakeSocialRepository()
        let model = await ReferralModel(repository: repo)
        await model.applyCode("   ")
        let phase = await model.applyPhase
        if case .failure(let msg) = phase {
            #expect(!msg.isEmpty)
        } else {
            Issue.record("Expected .failure for empty code, got \(phase)")
        }
        let recorded = await repo.recordedAppliedCodes
        #expect(recorded.isEmpty)
    }

    @Test("successful apply reloads the referral profile")
    func successReloadsProfile() async {
        let repo = FakeSocialRepository()
        let model = await ReferralModel(repository: repo)
        await model.applyCode("VALID01")
        // After success the model should have loaded the profile.
        let profile = await model.referralProfile
        #expect(profile != nil)
    }

    @Test("load sets phase to .loaded on success")
    func loadSetsPhaseToLoaded() async {
        let repo = FakeSocialRepository()
        let model = await ReferralModel(repository: repo)
        await model.load()
        let phase = await model.phase
        #expect(phase == .loaded)
    }

    @Test("load sets phase to .error on failure")
    func loadSetsPhaseToError() async {
        let repo = FakeSocialRepository(error: .offline)
        let model = await ReferralModel(repository: repo)
        await model.load()
        let phase = await model.phase
        if case .error = phase {
            // Expected
        } else {
            Issue.record("Expected .error phase, got \(phase)")
        }
    }
}

// MARK: - Endpoint tests

@Suite("ReferralEndpoints")
struct ReferralEndpointsTests {

    @Test("getReferralProfile builds correct path")
    func getReferralProfilePath() {
        let endpoint = Endpoints.getReferralProfile()
        #expect(endpoint.path == "/book/me/referrals")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth)
    }

    @Test("applyReferralCode builds POST with body")
    func applyReferralCodeEndpoint() throws {
        let endpoint = try Endpoints.applyReferralCode("ALICE42")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/me/referrals/apply")
        #expect(endpoint.httpBody != nil)
        #expect(endpoint.requiresAuth)
    }
}
