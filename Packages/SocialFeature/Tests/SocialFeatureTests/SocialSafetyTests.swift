import Testing
import Foundation
import Models
import CoreKit
import Networking
@testable import SocialFeature

// MARK: - ReportReason tolerant-decoding tests

@Suite("ReportReason")
struct ReportReasonTests {

    @Test("all known reason codes decode correctly")
    func knownReasonsDecode() throws {
        let cases: [(String, ReportReason)] = [
            ("harassment", .harassment),
            ("spam", .spam),
            ("inappropriate_content", .inappropriateContent),
            ("impersonation", .impersonation),
            ("other", .other),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ReportReason.self, from: json)
            #expect(decoded == expected, "Failed for raw value '\(raw)'")
        }
    }

    @Test("unknown reason decodes to .unknown — never crashes (RF2)")
    func unknownReasonTolerated() throws {
        let json = "\"future_reason_code\"".data(using: .utf8)!
        let reason = try JSONDecoder().decode(ReportReason.self, from: json)
        if case .unknown(let raw) = reason {
            #expect(raw == "future_reason_code")
        } else {
            Issue.record("Expected .unknown but got \(reason)")
        }
    }

    @Test("rawValue round-trips through encode/decode")
    func rawValueRoundTrips() throws {
        for reason in ReportReason.allDisplayCases {
            let encoded = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ReportReason.self, from: encoded)
            #expect(decoded == reason, "Round-trip failed for \(reason.rawValue)")
        }
    }

    @Test("displayLabel is non-empty for all display cases")
    func displayLabelNonEmpty() {
        for reason in ReportReason.allDisplayCases {
            #expect(!reason.displayLabel.isEmpty)
        }
    }

    @Test("allDisplayCases does not include .unknown")
    func allDisplayCasesExcludesUnknown() {
        let hasUnknown = ReportReason.allDisplayCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
    }
}

// MARK: - NudgeRateLimiter tests

@Suite("NudgeRateLimiter")
struct NudgeRateLimiterTests {

    private func makeLimiter(max: Int = 3, window: TimeInterval = 3600) -> NudgeRateLimiter {
        NudgeRateLimiter(
            maxNudgesPerWindow: max,
            windowDuration: window,
            defaults: UserDefaults(suiteName: "cf.test.\(UUID().uuidString)")!
        )
    }

    @Test("canSendNudge is true when no nudges sent")
    func canSendInitially() {
        let limiter = makeLimiter()
        #expect(limiter.canSendNudge(to: "partner-1"))
    }

    @Test("nudgesRemaining starts at max")
    func remainingStartsAtMax() {
        let limiter = makeLimiter(max: 3)
        #expect(limiter.nudgesRemaining(for: "partner-1") == 3)
    }

    @Test("recordNudge decrements remaining count")
    func recordNudgeDecrementsRemaining() {
        let limiter = makeLimiter(max: 3)
        limiter.recordNudge(to: "partner-1")
        #expect(limiter.nudgesRemaining(for: "partner-1") == 2)
        limiter.recordNudge(to: "partner-1")
        #expect(limiter.nudgesRemaining(for: "partner-1") == 1)
    }

    @Test("canSendNudge is false when cap is reached")
    func blocksAtCap() {
        let limiter = makeLimiter(max: 2)
        limiter.recordNudge(to: "partner-1")
        limiter.recordNudge(to: "partner-1")
        #expect(!limiter.canSendNudge(to: "partner-1"))
        #expect(limiter.nudgesRemaining(for: "partner-1") == 0)
    }

    @Test("rate limit is per-partner — other partners unaffected")
    func rateLimitIsPerPartner() {
        let limiter = makeLimiter(max: 1)
        limiter.recordNudge(to: "partner-A")
        #expect(!limiter.canSendNudge(to: "partner-A"))
        #expect(limiter.canSendNudge(to: "partner-B"))
    }

    @Test("nextAvailableDate is nil when nudges remain")
    func nextDateNilWhenAvailable() {
        let limiter = makeLimiter(max: 3)
        #expect(limiter.nextAvailableDate(for: "partner-1") == nil)
    }

    @Test("nextAvailableDate is non-nil when cap is reached")
    func nextDateNonNilWhenCapped() {
        let limiter = makeLimiter(max: 1)
        limiter.recordNudge(to: "partner-1")
        #expect(limiter.nextAvailableDate(for: "partner-1") != nil)
    }

    @Test("resetUsage restores full capacity")
    func resetRestoresCapacity() {
        let limiter = makeLimiter(max: 2)
        limiter.recordNudge(to: "partner-1")
        limiter.recordNudge(to: "partner-1")
        #expect(!limiter.canSendNudge(to: "partner-1"))
        limiter.resetUsage(for: "partner-1")
        #expect(limiter.canSendNudge(to: "partner-1"))
        #expect(limiter.nudgesRemaining(for: "partner-1") == 2)
    }

    @Test("expired nudges outside the window don't count toward the cap")
    func expiredNudgesNotCounted() {
        // Window of only 1 second — records from 5 s ago are stale.
        let limiter = makeLimiter(max: 1, window: 1)
        // Manually pre-seed an old timestamp via UserDefaults.
        let suite = "cf.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let oldTimestamp = Date(timeIntervalSinceNow: -5)
        let encoded = try? JSONEncoder().encode(["partner-1": [oldTimestamp]])
        defaults.set(encoded, forKey: "cf.nudgeRateLimit.usage")
        let limiter2 = NudgeRateLimiter(maxNudgesPerWindow: 1, windowDuration: 1, defaults: defaults)
        // Stale record should NOT count — limiter2 should allow a nudge.
        #expect(limiter2.canSendNudge(to: "partner-1"))
    }
}

// MARK: - FakeSocialRepository safety tests

@Suite("FakeSocialRepository Safety")
struct FakeSocialRepositorySafetyTests {

    @Test("blockUser marks userId as blocked")
    func blockUserMarksBlocked() async throws {
        let repo = FakeSocialRepository()
        try await repo.blockUser(userId: "user-x")
        let blocked = await repo.isBlocked(userId: "user-x")
        #expect(blocked)
    }

    @Test("unblockUser removes block")
    func unblockUserRemovesBlock() async throws {
        let repo = FakeSocialRepository(blockedUserIds: ["user-x"])
        try await repo.unblockUser(userId: "user-x")
        let blocked = await repo.isBlocked(userId: "user-x")
        #expect(!blocked)
    }

    @Test("isBlocked returns false for unknown userId")
    func isBlockedFalseForUnknown() async {
        let repo = FakeSocialRepository()
        let blocked = await repo.isBlocked(userId: "not-blocked")
        #expect(!blocked)
    }

    @Test("refreshBlockedUsers returns all blocked user IDs")
    func refreshBlockedUsersReturnsAll() async throws {
        let repo = FakeSocialRepository(blockedUserIds: ["user-a", "user-b"])
        let list = try await repo.refreshBlockedUsers()
        let ids = Set(list.map(\.userId))
        #expect(ids == ["user-a", "user-b"])
    }

    @Test("submitReport records targetUserId and reason")
    func submitReportRecords() async throws {
        let repo = FakeSocialRepository()
        _ = try await repo.submitReport(
            targetUserId: "user-bad",
            contentId: nil,
            contentType: nil,
            reason: .harassment,
            details: "They sent rude nudges"
        )
        let recorded = await repo.recordedReports
        #expect(recorded.count == 1)
        #expect(recorded[0].targetUserId == "user-bad")
        #expect(recorded[0].reason == .harassment)
    }

    @Test("submitReport returns a reportId")
    func submitReportReturnsId() async throws {
        let repo = FakeSocialRepository()
        let response = try await repo.submitReport(
            targetUserId: "user-spam",
            contentId: nil,
            contentType: nil,
            reason: .spam,
            details: nil
        )
        #expect(response.reportId != nil)
        #expect(response.status == "received")
    }

    @Test("forced error propagates through all safety methods")
    func forcedErrorPropagatesSafety() async {
        let repo = FakeSocialRepository(error: .offline)
        var caughtCount = 0

        do {
            try await repo.blockUser(userId: "x")
        } catch let e as AppError {
            #expect(e.code == "offline")
            caughtCount += 1
        } catch { Issue.record("unexpected: \(error)") }

        do {
            try await repo.unblockUser(userId: "x")
        } catch let e as AppError {
            #expect(e.code == "offline")
            caughtCount += 1
        } catch { Issue.record("unexpected: \(error)") }

        do {
            try await repo.refreshBlockedUsers()
        } catch let e as AppError {
            #expect(e.code == "offline")
            caughtCount += 1
        } catch { Issue.record("unexpected: \(error)") }

        do {
            _ = try await repo.submitReport(
                targetUserId: "x", contentId: nil, contentType: nil,
                reason: .other, details: nil
            )
        } catch let e as AppError {
            #expect(e.code == "offline")
            caughtCount += 1
        } catch { Issue.record("unexpected: \(error)") }

        #expect(caughtCount == 4)
    }
}

// MARK: - Safety endpoint shape tests

@Suite("SafetyEndpoints")
struct SafetyEndpointsTests {

    @Test("blockUser builds POST /book/me/blocks with body")
    func blockUserEndpoint() throws {
        let endpoint = try Endpoints.blockUser(userId: "user-bad")
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/me/blocks")
        #expect(endpoint.httpBody != nil)
        #expect(endpoint.requiresAuth)
    }

    @Test("unblockUser builds DELETE /book/me/blocks/{userId}")
    func unblockUserEndpoint() {
        let endpoint = Endpoints.unblockUser(userId: "user-bad")
        #expect(endpoint.method == .delete)
        #expect(endpoint.path == "/book/me/blocks/user-bad")
        #expect(endpoint.requiresAuth)
    }

    @Test("getBlockedUsers builds GET /book/me/blocks")
    func getBlockedUsersEndpoint() {
        let endpoint = Endpoints.getBlockedUsers()
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/book/me/blocks")
        #expect(endpoint.requiresAuth)
    }

    @Test("submitReport builds POST /book/moderation/reports with body")
    func submitReportEndpoint() throws {
        let endpoint = try Endpoints.submitReport(
            targetUserId: "user-bad",
            contentId: nil,
            contentType: nil,
            reason: "harassment",
            details: "Rude nudges"
        )
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/moderation/reports")
        #expect(endpoint.httpBody != nil)
        #expect(endpoint.requiresAuth)
    }

    @Test("submitReport body encodes targetUserId and reason")
    func submitReportBodyContents() throws {
        let endpoint = try Endpoints.submitReport(
            targetUserId: "user-abc",
            contentId: nil,
            contentType: nil,
            reason: "spam",
            details: nil
        )
        guard let body = endpoint.httpBody else {
            Issue.record("httpBody is nil")
            return
        }
        let dict = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(dict?["targetUserId"] as? String == "user-abc")
        #expect(dict?["reason"] as? String == "spam")
    }
}

// MARK: - BlockedUser evolution tests (RF2)

@Suite("BlockedUser Evolution")
struct BlockedUserEvolutionTests {

    @Test("BlockedUser decodes without blockedAt field")
    func decodesWithoutBlockedAt() throws {
        let json = """
        {"userId":"user-abc"}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(BlockedUser.self, from: json)
        #expect(user.userId == "user-abc")
        #expect(user.blockedAt == nil)
    }

    @Test("BlockedUsersResponse decodes empty list without crashing")
    func decodesEmptyList() throws {
        let json = """
        {"blockedUsers":[]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(BlockedUsersResponse.self, from: json)
        #expect(response.blockedUsers.isEmpty)
    }

    @Test("ReportResponse tolerates missing fields")
    func reportResponseToleratesMissingFields() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(ReportResponse.self, from: json)
        #expect(response.reportId == nil)
        #expect(response.status == nil)
    }
}
