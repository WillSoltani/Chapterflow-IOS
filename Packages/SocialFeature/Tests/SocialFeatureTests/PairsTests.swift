import Testing
import Foundation
import Models
import CoreKit
@testable import SocialFeature

// MARK: - PairStatus RF2 evolution tests

@Suite("PairStatus")
struct PairStatusTests {

    @Test("all known statuses decode")
    func knownStatuses() throws {
        let cases: [(String, PairStatus)] = [
            ("active", .active), ("pending", .pending), ("expired", .expired),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(PairStatus.self, from: json)
            #expect(decoded == expected)
        }
    }

    @Test("unknown status decodes to .unknown — never crashes")
    func unknownStatusTolerated() throws {
        let json = "\"vip_only\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(PairStatus.self, from: json)
        if case .unknown(let raw) = status {
            #expect(raw == "vip_only")
        } else {
            Issue.record("Expected .unknown but got \(status)")
        }
    }

    @Test("unknown status has non-empty displayLabel — no crash in views")
    func unknownDisplayLabel() {
        let status = PairStatus.unknown("galactic_pair")
        #expect(!status.displayLabel.isEmpty)
    }

    @Test("known status displayLabels are human-readable")
    func knownDisplayLabels() {
        #expect(!PairStatus.active.displayLabel.isEmpty)
        #expect(!PairStatus.pending.displayLabel.isEmpty)
        #expect(!PairStatus.expired.displayLabel.isEmpty)
    }
}

// MARK: - ReadingPair decoding tests

@Suite("ReadingPair")
struct ReadingPairTests {

    @Test("active pair decodes correctly from full JSON")
    func activePairFullDecoding() throws {
        let json = """
        {
          "partnerId": "user-alice",
          "partnerDisplayName": "Alice",
          "partnerAvatarUrl": null,
          "partnerAvatarEmoji": "📚",
          "partnerTier": "analyst",
          "partnerCurrentStreak": 14,
          "partnerBooksFinished": 7,
          "status": "active",
          "pairedAt": "2024-03-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let pair = try JSONDecoder().decode(ReadingPair.self, from: json)
        #expect(pair.partnerId == "user-alice")
        #expect(pair.partnerDisplayName == "Alice")
        #expect(pair.partnerTier == .analyst)
        #expect(pair.partnerCurrentStreak == 14)
        #expect(pair.status == .active)
        #expect(pair.pairedAt != nil)
    }

    @Test("pair with unknown status decodes tolerantly")
    func pairUnknownStatusTolerated() throws {
        let json = """
        {
          "partnerId": "user-bob",
          "partnerTier": "reader",
          "partnerCurrentStreak": 0,
          "partnerBooksFinished": 0,
          "status": "suspended"
        }
        """.data(using: .utf8)!
        let pair = try JSONDecoder().decode(ReadingPair.self, from: json)
        if case .unknown(let raw) = pair.status {
            #expect(raw == "suspended")
        } else {
            Issue.record("Expected .unknown status")
        }
    }

    @Test("pair with unknown tier decodes tolerantly")
    func pairUnknownTierTolerated() throws {
        let json = """
        {
          "partnerId": "user-carol",
          "partnerTier": "future_tier",
          "partnerCurrentStreak": 0,
          "partnerBooksFinished": 0,
          "status": "active"
        }
        """.data(using: .utf8)!
        let pair = try JSONDecoder().decode(ReadingPair.self, from: json)
        if case .unknown(let raw) = pair.partnerTier {
            #expect(raw == "future_tier")
        } else {
            Issue.record("Expected .unknown tier")
        }
    }

    @Test("pair initials from two-word display name")
    func pairInitialsTwoWords() {
        let pair = ReadingPair(
            partnerId: "u1", partnerDisplayName: "Bob Smith",
            partnerAvatarUrl: nil, partnerAvatarEmoji: nil,
            partnerTier: .reader, partnerCurrentStreak: 0,
            partnerBooksFinished: 0, status: .active, pairedAt: nil
        )
        #expect(pair.initials == "BS")
    }

    @Test("pair initials from single-word display name")
    func pairInitialsSingleWord() {
        let pair = ReadingPair(
            partnerId: "u2", partnerDisplayName: "Alice",
            partnerAvatarUrl: nil, partnerAvatarEmoji: nil,
            partnerTier: .reader, partnerCurrentStreak: 0,
            partnerBooksFinished: 0, status: .active, pairedAt: nil
        )
        #expect(pair.initials == "A")
    }

    @Test("pair initials fallback when nil displayName")
    func pairInitialsNil() {
        let pair = ReadingPair(
            partnerId: "u3", partnerDisplayName: nil,
            partnerAvatarUrl: nil, partnerAvatarEmoji: nil,
            partnerTier: .reader, partnerCurrentStreak: 0,
            partnerBooksFinished: 0, status: .active, pairedAt: nil
        )
        #expect(pair.initials == "?")
    }

    @Test("PairsListResponse decodes envelope with multiple pairs")
    func pairsListResponseEnvelope() throws {
        let json = """
        {
          "pairs": [
            { "partnerId": "p1", "partnerTier": "reader", "partnerCurrentStreak": 0,
              "partnerBooksFinished": 0, "status": "active" },
            { "partnerId": "p2", "partnerTier": "analyst", "partnerCurrentStreak": 5,
              "partnerBooksFinished": 2, "status": "pending" }
          ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(PairsListResponse.self, from: json)
        #expect(response.pairs.count == 2)
        #expect(response.pairs[0].status == .active)
        #expect(response.pairs[1].status == .pending)
    }

    @Test("PairInvite decodes with and without expiresAt")
    func pairInviteDecoding() throws {
        let withExpiry = """
        { "code": "ABCD-1234", "inviteLink": "https://app.chapterflow.ca/pair/ABCD-1234",
          "expiresAt": "2024-12-31T23:59:59Z" }
        """.data(using: .utf8)!
        let withoutExpiry = """
        { "code": "WXYZ-5678", "inviteLink": "https://app.chapterflow.ca/pair/WXYZ-5678" }
        """.data(using: .utf8)!
        let invite1 = try JSONDecoder().decode(PairInvite.self, from: withExpiry)
        let invite2 = try JSONDecoder().decode(PairInvite.self, from: withoutExpiry)
        #expect(invite1.code == "ABCD-1234")
        #expect(invite1.expiresAt != nil)
        #expect(invite2.code == "WXYZ-5678")
        #expect(invite2.expiresAt == nil)
    }
}

// MARK: - PairsModel tests

@Suite("PairsModel")
@MainActor
struct PairsModelTests {

    @Test("load populates pairs on success")
    func loadPopulatesPairs() async {
        let repo = FakeSocialRepository(pairs: [.previewActive, .previewPending])
        let model = PairsModel(repository: repo)
        await model.load()
        #expect(model.pairs.count == 2)
        #expect(model.activePairs.count == 1)
        #expect(model.pendingPairs.count == 1)
        #expect(model.expiredPairs.isEmpty)
    }

    @Test("load sets error phase on failure")
    func loadSetsErrorPhase() async {
        let repo = FakeSocialRepository(error: .offline)
        let model = PairsModel(repository: repo)
        await model.load()
        if case .error = model.phase { /* pass */ } else {
            Issue.record("Expected .error phase but got \(model.phase)")
        }
    }

    @Test("acceptInvite with valid code adds pair")
    func acceptInviteAddsNewPair() async throws {
        let repo = FakeSocialRepository()
        let model = PairsModel(repository: repo)
        let pair = try await model.acceptInvite(code: "ABCD-1234")
        #expect(pair.partnerId == "accepted-ABCD-1234")
    }

    @Test("acceptInvite with empty code throws .invalidInput")
    func acceptInviteEmptyCodeThrows() async {
        let repo = FakeSocialRepository()
        let model = PairsModel(repository: repo)
        do {
            _ = try await model.acceptInvite(code: "   ")
            Issue.record("Expected throw but returned normally")
        } catch let e as AppError {
            if case .invalidInput = e { /* expected */ } else { Issue.record("Expected .invalidInput, got \(e)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("nudge records in fake and sets lastNudgedPartnerId")
    func nudgeRecordsAndSetsLastNudged() async {
        let repo = FakeSocialRepository(pairs: [.previewActive])
        let model = PairsModel(repository: repo)
        await model.load()
        await model.nudge(partnerId: ReadingPair.previewActive.partnerId)
        #expect(model.lastNudgedPartnerId == ReadingPair.previewActive.partnerId)
        let recorded = await repo.recordedNudges
        #expect(recorded.contains(ReadingPair.previewActive.partnerId))
    }

    @Test("unpair removes partner from the list")
    func unpairRemovesPartner() async {
        let repo = FakeSocialRepository(pairs: [.previewActive, .previewExpired])
        let model = PairsModel(repository: repo)
        await model.load()
        #expect(model.pairs.count == 2)
        await model.unpair(partnerId: ReadingPair.previewActive.partnerId)
        #expect(model.pairs.count == 1)
        #expect(model.operationError == nil)
    }

    @Test("nudge failure sets operationError")
    func nudgeFailureSetsError() async {
        let repo = FakeSocialRepository(error: .offline)
        let model = PairsModel(repository: repo)
        await model.nudge(partnerId: "any-partner")
        #expect(model.operationError != nil)
    }

    @Test("expiredPairs filtered correctly")
    func expiredPairsFiltered() async {
        let repo = FakeSocialRepository(pairs: [.previewActive, .previewPending, .previewExpired])
        let model = PairsModel(repository: repo)
        await model.load()
        #expect(model.activePairs.count == 1)
        #expect(model.pendingPairs.count == 1)
        #expect(model.expiredPairs.count == 1)
    }
}

// MARK: - Deep-link pair accept tests

@Suite("DeepLinkPair")
struct DeepLinkPairTests {

    @Test("pairAccept deep link extracted from chapterflow:// URL")
    func pairAcceptDeepLinkParsed() {
        let url = URL(string: "chapterflow://pair/accept/ABCD-1234")!
        let deepLink = DeepLink(url: url)
        if case .pairAccept(let code) = deepLink {
            #expect(code == "ABCD-1234")
        } else {
            Issue.record("Expected .pairAccept deep link for \(url)")
        }
    }

    @Test("non-pair chapterflow URL does not produce pairAccept")
    func nonPairURLIgnored() {
        let url = URL(string: "chapterflow://library/book-123")!
        let deepLink = DeepLink(url: url)
        if case .pairAccept = deepLink {
            Issue.record("Should not parse \(url) as pairAccept")
        }
    }
}
