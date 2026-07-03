import Testing
import Foundation
import CoreKit
import Networking
@testable import SocialFeature

// MARK: - Gift model decoding

@Suite("Gift")
struct GiftTests {

    @Test("Gift decodes from JSON with known status")
    func giftDecodesKnownStatus() throws {
        let json = """
        {
          "code": "GIFT1234",
          "giftType": "pro_week",
          "senderDisplayName": "Alice",
          "status": "pending",
          "createdAt": "2026-07-03T10:00:00Z",
          "expiresAt": "2026-07-10T10:00:00Z"
        }
        """.data(using: .utf8)!
        let gift = try JSONDecoder().decode(Gift.self, from: json)
        #expect(gift.code == "GIFT1234")
        #expect(gift.giftType == "pro_week")
        #expect(gift.status == .pending)
        #expect(gift.senderDisplayName == "Alice")
    }

    @Test("Gift decodes with null optional fields")
    func giftDecodesNullOptionals() throws {
        let json = """
        {
          "code": "GIFT9999",
          "giftType": "pro_month",
          "senderDisplayName": null,
          "status": "claimed",
          "createdAt": null,
          "expiresAt": null
        }
        """.data(using: .utf8)!
        let gift = try JSONDecoder().decode(Gift.self, from: json)
        #expect(gift.status == .claimed)
        #expect(gift.senderDisplayName == nil)
        #expect(gift.expiresAt == nil)
    }

    @Test("Unknown GiftStatus decodes to .unknown — never crashes")
    func unknownStatusToleratedDecoding() throws {
        let json = """
        {
          "code": "GIFT0000",
          "giftType": "pro_week",
          "status": "voided",
          "senderDisplayName": null,
          "createdAt": null,
          "expiresAt": null
        }
        """.data(using: .utf8)!
        let gift = try JSONDecoder().decode(Gift.self, from: json)
        if case .unknown(let raw) = gift.status {
            #expect(raw == "voided")
        } else {
            Issue.record("Expected .unknown but got \(gift.status)")
        }
    }

    @Test("GiftStatus evolution: all known values decode")
    func giftStatusKnownValues() throws {
        let cases: [(String, GiftStatus)] = [
            ("pending", .pending),
            ("claimed", .claimed),
            ("expired", .expired),
        ]
        for (raw, expected) in cases {
            let data = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(GiftStatus.self, from: data)
            #expect(decoded == expected, "Failed for '\(raw)'")
        }
    }

    @Test("GiftPreviewResponse decodes envelope")
    func giftPreviewResponseEnvelope() throws {
        let json = """
        {
          "gift": {
            "code": "GIFT5678",
            "giftType": "pro_week",
            "senderDisplayName": "Bob",
            "status": "pending",
            "createdAt": "2026-07-01T00:00:00Z",
            "expiresAt": "2026-07-08T00:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GiftPreviewResponse.self, from: json)
        #expect(response.gift.code == "GIFT5678")
        #expect(response.gift.status == .pending)
    }

    @Test("GiftClaimResponse decodes with optional message")
    func giftClaimResponseWithMessage() throws {
        let json = """
        {
          "gift": {
            "code": "GIFT5678",
            "giftType": "pro_week",
            "senderDisplayName": "Bob",
            "status": "claimed",
            "createdAt": null,
            "expiresAt": null
          },
          "message": "Pro access activated for 7 days!"
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GiftClaimResponse.self, from: json)
        #expect(response.gift.status == .claimed)
        #expect(response.message == "Pro access activated for 7 days!")
    }

    @Test("GiftClaimResponse decodes without optional message")
    func giftClaimResponseWithoutMessage() throws {
        let json = """
        {
          "gift": {
            "code": "GIFT5678",
            "giftType": "pro_week",
            "senderDisplayName": null,
            "status": "claimed",
            "createdAt": null,
            "expiresAt": null
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GiftClaimResponse.self, from: json)
        #expect(response.message == nil)
    }

    @Test("Gift.giftTypeLabel maps pro_week correctly")
    func giftTypeLabelProWeek() {
        let gift = Gift.previewPending
        #expect(gift.giftTypeLabel == "1 Week of Pro")
    }

    @Test("Gift.giftTypeLabel falls back to raw value for unknown types")
    func giftTypeLabelUnknown() {
        let gift = Gift(
            code: "X", giftType: "pro_year",
            senderDisplayName: nil, status: .pending,
            createdAt: nil, expiresAt: nil
        )
        #expect(gift.giftTypeLabel == "pro_year")
    }
}

// MARK: - FakeSocialRepository gift behaviour

@Suite("FakeSocialRepositoryGifts")
struct FakeSocialRepositoryGiftTests {

    @Test("createGift returns a pending gift with a unique code")
    func createGiftReturnsPendingGift() async throws {
        let repo = FakeSocialRepository.loaded
        let gift = try await repo.createGift(giftType: "pro_week")
        #expect(gift.giftType == "pro_week")
        #expect(gift.status == .pending)
        #expect(!gift.code.isEmpty)
    }

    @Test("createGift codes are unique across calls")
    func createGiftCodesUnique() async throws {
        let repo = FakeSocialRepository.loaded
        let a = try await repo.createGift(giftType: "pro_week")
        let b = try await repo.createGift(giftType: "pro_week")
        #expect(a.code != b.code)
    }

    @Test("getGift returns the seeded gift")
    func getGiftReturnsSeededGift() async throws {
        let repo = FakeSocialRepository.withPendingGift
        let gift = try await repo.getGift(code: "GIFT0001")
        #expect(gift.code == "GIFT0001")
        #expect(gift.status == .pending)
    }

    @Test("getGift throws notFound for unknown code")
    func getGiftNotFound() async {
        let repo = FakeSocialRepository.loaded
        do {
            _ = try await repo.getGift(code: "INVALID")
            Issue.record("Expected error but succeeded")
        } catch let err as AppError {
            #expect(err.code == "not_found")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("claimGift transitions pending gift to claimed")
    func claimGiftSucceeds() async throws {
        let repo = FakeSocialRepository.withPendingGift
        let result = try await repo.claimGift(code: "GIFT0001")
        #expect(result.gift.status == .claimed)
        #expect(result.message != nil)
        let updated = try await repo.getGift(code: "GIFT0001")
        #expect(updated.status == .claimed)
    }

    @Test("claimGift throws gift_already_claimed when already redeemed")
    func claimGiftAlreadyClaimed() async {
        let repo = FakeSocialRepository.withClaimedGift
        do {
            _ = try await repo.claimGift(code: "CLMD0001")
            Issue.record("Expected error but succeeded")
        } catch let err as AppError {
            #expect(err.code == "gift_already_claimed")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("claimGift throws notFound for unknown code")
    func claimGiftNotFound() async {
        let repo = FakeSocialRepository.loaded
        do {
            _ = try await repo.claimGift(code: "UNKNOWN")
            Issue.record("Expected error but succeeded")
        } catch let err as AppError {
            #expect(err.code == "not_found")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("forced error propagates from all gift methods")
    func forcedErrorPropagatesFromGiftMethods() async {
        let repo = FakeSocialRepository(error: .offline)
        var caughtCount = 0
        do { _ = try await repo.getGift(code: "X") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.claimGift(code: "X") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        do { _ = try await repo.createGift(giftType: "pro_week") } catch let e as AppError { #expect(e.code == "offline"); caughtCount += 1 } catch { Issue.record("unexpected: \(error)") }
        #expect(caughtCount == 3)
    }
}

// MARK: - Gift endpoints

@Suite("GiftEndpoints")
struct GiftEndpointTests {

    @Test("getGift builds correct path")
    func getGiftPath() {
        let endpoint = Endpoints.getGift(code: "GIFT1234")
        #expect(endpoint.path == "/book/me/gifts/GIFT1234")
        #expect(endpoint.method == .get)
        #expect(endpoint.requiresAuth)
    }

    @Test("claimGift builds correct POST path")
    func claimGiftPath() throws {
        let endpoint = try Endpoints.claimGift(code: "GIFT1234")
        #expect(endpoint.path == "/book/me/gifts/GIFT1234/claim")
        #expect(endpoint.method == .post)
        #expect(endpoint.requiresAuth)
    }

    @Test("createGift builds correct POST path with body")
    func createGiftPath() throws {
        let endpoint = try Endpoints.createGift(giftType: "pro_week")
        #expect(endpoint.path == "/book/me/gifts")
        #expect(endpoint.method == .post)
        #expect(endpoint.httpBody != nil)
        #expect(endpoint.requiresAuth)
    }
}

// MARK: - DeepLink gift parsing

@Suite("DeepLinkGift")
struct DeepLinkGiftTests {

    @Test("chapterflow://gift/{code} parses to .gift")
    func giftDeepLinkParses() {
        let url = URL(string: "chapterflow://gift/GIFT1234")!
        let link = DeepLink(url: url)
        if case .gift(let code) = link {
            #expect(code == "GIFT1234")
        } else {
            Issue.record("Expected .gift but got \(String(describing: link))")
        }
    }

    @Test("chapterflow://gift/ without code parses to .unknown")
    func giftDeepLinkMissingCode() {
        let url = URL(string: "chapterflow://gift/")!
        let link = DeepLink(url: url)
        if case .gift = link {
            Issue.record("Expected .unknown for empty code segment")
        }
    }
}
