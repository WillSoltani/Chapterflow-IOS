import Testing
import Foundation
@testable import RichNotificationCore

@Suite("PushPayloadParser")
struct PushPayloadParserTests {

    // MARK: - typeRaw

    @Test("typeRaw is extracted from 'type' key")
    func typeRawExtracted() {
        let payload = PushPayloadParser.parse(["type": "badge_earned"])
        #expect(payload.typeRaw == "badge_earned")
    }

    @Test("missing type key yields empty string, not crash (RF2)")
    func missingTypeYieldsEmptyString() {
        let payload = PushPayloadParser.parse([:])
        #expect(payload.typeRaw == "")
    }

    // MARK: - imageURL

    @Test("HTTPS imageURL is accepted")
    func httpsImageURLAccepted() {
        let payload = PushPayloadParser.parse(["imageURL": "https://cdn.example.com/badge.png"])
        #expect(payload.imageURL?.absoluteString == "https://cdn.example.com/badge.png")
    }

    @Test("HTTP imageURL is rejected for security")
    func httpImageURLRejected() {
        let payload = PushPayloadParser.parse(["imageURL": "http://cdn.example.com/badge.png"])
        #expect(payload.imageURL == nil)
    }

    @Test("image_url snake_case key is accepted")
    func snakeCaseImageURLKey() {
        let payload = PushPayloadParser.parse(["image_url": "https://cdn.example.com/img.jpg"])
        #expect(payload.imageURL != nil)
    }

    @Test("invalid URL string yields nil imageURL without crash")
    func invalidImageURLYieldsNil() {
        let payload = PushPayloadParser.parse(["imageURL": "not a url !!"])
        #expect(payload.imageURL == nil)
    }

    @Test("empty imageURL string yields nil")
    func emptyImageURLYieldsNil() {
        let payload = PushPayloadParser.parse(["imageURL": ""])
        #expect(payload.imageURL == nil)
    }

    // MARK: - deepLink

    @Test("chapterflow:// deepLink is accepted")
    func chapterflowDeepLinkAccepted() {
        let payload = PushPayloadParser.parse(["deepLink": "chapterflow://engagement"])
        #expect(payload.deepLink?.absoluteString == "chapterflow://engagement")
    }

    @Test("https deepLink is rejected — wrong scheme")
    func httpsDeepLinkRejected() {
        let payload = PushPayloadParser.parse(["deepLink": "https://example.com"])
        #expect(payload.deepLink == nil)
    }

    @Test("deep_link snake_case key is accepted")
    func snakeCaseDeepLink() {
        let payload = PushPayloadParser.parse(["deep_link": "chapterflow://review"])
        #expect(payload.deepLink?.absoluteString == "chapterflow://review")
    }

    // MARK: - chapterNumber

    @Test("chapterNumber as Int is parsed")
    func chapterNumberAsInt() {
        let payload = PushPayloadParser.parse(["chapterNumber": 7])
        #expect(payload.chapterNumber == 7)
    }

    @Test("chapterNumber as String is parsed")
    func chapterNumberAsString() {
        let payload = PushPayloadParser.parse(["chapterNumber": "12"])
        #expect(payload.chapterNumber == 12)
    }

    @Test("chapter_number snake_case key is parsed")
    func snakeCaseChapterNumber() {
        let payload = PushPayloadParser.parse(["chapter_number": 3])
        #expect(payload.chapterNumber == 3)
    }

    @Test("missing chapterNumber yields nil without crash")
    func missingChapterNumber() {
        let payload = PushPayloadParser.parse([:])
        #expect(payload.chapterNumber == nil)
    }

    @Test("non-numeric chapterNumber string yields nil")
    func nonNumericChapterNumber() {
        let payload = PushPayloadParser.parse(["chapterNumber": "abc"])
        #expect(payload.chapterNumber == nil)
    }

    // MARK: - badgeKey + badgeName

    @Test("badgeKey is extracted")
    func badgeKeyExtracted() {
        let payload = PushPayloadParser.parse(["badgeKey": "first_chapter"])
        #expect(payload.badgeKey == "first_chapter")
    }

    @Test("badge_key snake_case is accepted")
    func badgeKeySnakeCase() {
        let payload = PushPayloadParser.parse(["badge_key": "week_streak"])
        #expect(payload.badgeKey == "week_streak")
    }

    @Test("badgeName is extracted")
    func badgeNameExtracted() {
        let payload = PushPayloadParser.parse(["badgeName": "First Chapter"])
        #expect(payload.badgeName == "First Chapter")
    }

    @Test("badge_name snake_case is accepted")
    func badgeNameSnakeCase() {
        let payload = PushPayloadParser.parse(["badge_name": "Week Streak"])
        #expect(payload.badgeName == "Week Streak")
    }

    // MARK: - bookId

    @Test("bookId is extracted")
    func bookIdExtracted() {
        let payload = PushPayloadParser.parse(["bookId": "abc-123"])
        #expect(payload.bookId == "abc-123")
    }

    @Test("book_id snake_case is accepted")
    func bookIdSnakeCase() {
        let payload = PushPayloadParser.parse(["book_id": "xyz-789"])
        #expect(payload.bookId == "xyz-789")
    }

    // MARK: - RF2 safety

    @Test("RF2: completely empty payload never crashes")
    func emptyPayloadSafe() {
        let payload = PushPayloadParser.parse([:])
        #expect(payload.typeRaw == "")
        #expect(payload.imageURL == nil)
        #expect(payload.badgeKey == nil)
        #expect(payload.badgeName == nil)
        #expect(payload.bookId == nil)
        #expect(payload.chapterNumber == nil)
        #expect(payload.deepLink == nil)
    }

    @Test("RF2: unexpected extra keys do not crash")
    func extraKeysSafe() {
        let payload = PushPayloadParser.parse([
            "type": "badge_earned",
            "future_key_2027": "some_value",
            "nested_data": ["key": "value"]
        ])
        #expect(payload.typeRaw == "badge_earned")
    }

    @Test("RF2: unknown type value parses without crash")
    func unknownTypeSafe() {
        let payload = PushPayloadParser.parse(["type": "a_brand_new_server_type_2026"])
        #expect(payload.typeRaw == "a_brand_new_server_type_2026")
    }
}
