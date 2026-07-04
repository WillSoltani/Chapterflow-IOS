import Foundation
import Testing
@testable import SocialFeature
import Models
import CoreKit

// MARK: - ShareCardType tests

@Suite("ShareCardType")
struct ShareCardTypeTests {
    @Test("Known raw values decode correctly")
    func knownRawValues() {
        #expect(ShareCardType(rawValue: "chapter") == .chapter)
        #expect(ShareCardType(rawValue: "badge")   == .badge)
        #expect(ShareCardType(rawValue: "streak")  == .streak)
        #expect(ShareCardType(rawValue: "book")    == .book)
    }

    @Test("Case-insensitive decoding")
    func caseInsensitive() {
        #expect(ShareCardType(rawValue: "CHAPTER") == .chapter)
        #expect(ShareCardType(rawValue: "Streak")  == .streak)
    }

    @Test("Unknown raw values produce .unknown — never crash")
    func unknownRawValue() {
        let type = ShareCardType(rawValue: "future_type_v99")
        if case .unknown(let raw) = type {
            #expect(raw == "future_type_v99")
        } else {
            Issue.record("Expected .unknown case")
        }
    }

    @Test("rawValue round-trips for all known cases")
    func roundTrip() {
        let cases: [ShareCardType] = [.chapter, .badge, .streak, .book]
        for cardType in cases {
            #expect(ShareCardType(rawValue: cardType.rawValue) == cardType)
        }
    }

    @Test("Codable encode/decode round-trips")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for cardType in [ShareCardType.chapter, .badge, .streak, .book] {
            let data = try encoder.encode(cardType)
            let decoded = try decoder.decode(ShareCardType.self, from: data)
            #expect(decoded == cardType)
        }
    }

    @Test("Unknown Codable value decodes to .unknown — never throws")
    func unknownCodable() throws {
        let data = try JSONEncoder().encode("completely_new_type")
        let decoded = try JSONDecoder().decode(ShareCardType.self, from: data)
        if case .unknown(let raw) = decoded {
            #expect(raw == "completely_new_type")
        } else {
            Issue.record("Expected .unknown case")
        }
    }
}

// MARK: - ShareEventDestination tests

@Suite("ShareEventDestination")
struct ShareEventDestinationTests {
    @Test("Known raw values decode correctly")
    func knownRawValues() {
        #expect(ShareEventDestination(rawValue: "instagram") == .instagram)
        #expect(ShareEventDestination(rawValue: "twitter")   == .twitter)
        #expect(ShareEventDestination(rawValue: "messages")  == .messages)
        #expect(ShareEventDestination(rawValue: "other")     == .other)
    }

    @Test("Unknown raw values produce .unknown — never crash")
    func unknownRawValue() {
        let dest = ShareEventDestination(rawValue: "tiktok_v2")
        if case .unknown(let raw) = dest {
            #expect(raw == "tiktok_v2")
        } else {
            Issue.record("Expected .unknown case")
        }
    }
}

// MARK: - ShareEventBody tests

@Suite("ShareEventBody")
struct ShareEventBodyTests {
    @Test("Encodes cardType and destination raw values")
    func encodesRawValues() throws {
        let body = ShareEventBody(cardType: .streak, destination: .instagram)
        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["cardType"] == "streak")
        #expect(json?["destination"] == "instagram")
    }

    @Test("Unknown enum values preserve raw strings in encoded body")
    func unknownEnumPreservesString() throws {
        let body = ShareEventBody(
            cardType: .unknown("future_card"),
            destination: .unknown("future_dest")
        )
        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["cardType"] == "future_card")
        #expect(json?["destination"] == "future_dest")
    }
}

// MARK: - ShareCardInput tests

@Suite("ShareCardInput")
struct ShareCardInputTests {
    @Test("cardType returns correct type for each variant")
    func cardTypeMapping() {
        let chapter = ShareCardInput.chapter(
            bookTitle: "Test", bookEmoji: "📚",
            chapterNumber: 1, chapterTitle: "Intro",
            userName: nil, tier: .reader, referralCode: nil
        )
        let badge = ShareCardInput.badge(
            badgeName: "Badge", badgeDescription: "",
            badgeIcon: nil, category: "reading",
            userName: nil, tier: .reader, referralCode: nil
        )
        let streak = ShareCardInput.streak(
            days: 7, userName: nil, tier: .reader, referralCode: nil
        )
        let book = ShareCardInput.book(
            bookTitle: "Book", bookEmoji: "📖",
            authorName: nil, totalChapters: 5,
            userName: nil, tier: .reader, referralCode: nil
        )

        #expect(chapter.cardType == .chapter)
        #expect(badge.cardType == .badge)
        #expect(streak.cardType == .streak)
        #expect(book.cardType == .book)
    }

    @Test("referralLink builds chapterflow URL from code")
    func referralLinkBuilding() {
        let input = ShareCardInput.streak(
            days: 30, userName: "Alice", tier: .analyst, referralCode: "ALICE42"
        )
        #expect(input.referralLink == "chapterflow.app/ref/ALICE42")
    }

    @Test("referralLink is nil when no code provided")
    func referralLinkNilWhenNoCode() {
        let input = ShareCardInput.streak(
            days: 30, userName: "Alice", tier: .analyst, referralCode: nil
        )
        #expect(input.referralLink == nil)
    }

    @Test("referralLink works for all card types")
    func referralLinkAllTypes() {
        let code = "TEST99"
        let inputs: [ShareCardInput] = [
            .chapter(bookTitle: "B", bookEmoji: "📚", chapterNumber: 1,
                     chapterTitle: "C", userName: nil, tier: .reader, referralCode: code),
            .badge(badgeName: "B", badgeDescription: "", badgeIcon: nil,
                   category: "reading", userName: nil, tier: .reader, referralCode: code),
            .streak(days: 5, userName: nil, tier: .reader, referralCode: code),
            .book(bookTitle: "B", bookEmoji: "📚", authorName: nil,
                  totalChapters: 3, userName: nil, tier: .reader, referralCode: code),
        ]
        for input in inputs {
            #expect(input.referralLink == "chapterflow.app/ref/\(code)")
        }
    }
}

// MARK: - FakeSocialRepository share event recording

@Suite("FakeSocialRepository — share events")
struct FakeShareEventTests {
    @Test("Records share events in order")
    func recordsEvents() async throws {
        let repo = FakeSocialRepository()
        try await repo.postShareEvent(cardType: .chapter, destination: .instagram)
        try await repo.postShareEvent(cardType: .streak, destination: .other)

        let events = await repo.recordedShareEvents
        #expect(events.count == 2)
        #expect(events[0].0 == .chapter)
        #expect(events[0].1 == .instagram)
        #expect(events[1].0 == .streak)
        #expect(events[1].1 == .other)
    }

    @Test("Throws when forced error is set")
    func throwsOnForcedError() async {
        let repo = FakeSocialRepository(error: .offline)
        do {
            try await repo.postShareEvent(cardType: .badge, destination: .other)
            Issue.record("Expected an error to be thrown")
        } catch let error as AppError {
            if case .offline = error { /* expected */ } else {
                Issue.record("Expected .offline, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
