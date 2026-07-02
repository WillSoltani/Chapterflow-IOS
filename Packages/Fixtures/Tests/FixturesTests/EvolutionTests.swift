import Testing
import Foundation
import Models
@testable import Fixtures

// MARK: - Helpers

/// Load a fixture resource file as raw `Data` via the Fixtures module bundle.
private func fixtureData(_ name: String) throws -> Data {
    try Fixtures.rawData(name)
}

/// Re-encode a top-level JSON object after applying `transform`, then decode as `T`.
private func roundTrip<T: Decodable>(
    fixture name: String,
    as type: T.Type,
    mutate transform: (inout [String: Any]) -> Void
) throws -> T {
    var obj = try JSONSerialization.jsonObject(
        with: try fixtureData(name)
    ) as! [String: Any]
    transform(&obj)
    let mutated = try JSONSerialization.data(withJSONObject: obj)
    return try JSONDecoder.chapterFlow.decode(T.self, from: mutated)
}

/// Inject an unknown enum value at a JSON key path (single level).
private func injectUnknownEnum(
    in obj: inout [String: Any],
    key: String,
    unknown value: String = "future_unknown_value"
) {
    obj[key] = value
}

// MARK: - catalog.json mutations

@Suite("catalog.json — server evolution mutations")
struct CatalogFixtureEvolutionTests {

    @Test("unknown variantFamily in one book → that book still decodes (unknown case)")
    func unknownVariantFamily() throws {
        // Mutate the first book's variantFamily to an unknown value
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("catalog")) as! [String: Any]
        var books = obj["books"] as! [[String: Any]]
        books[0]["variantFamily"] = "DELTA"
        obj["books"] = books
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 3)
        #expect(response.books[0].variantFamily == .unknown("DELTA"))
    }

    @Test("extra future fields in book → silently ignored, decode succeeds")
    func extraFieldsInBook() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("catalog")) as! [String: Any]
        var books = obj["books"] as! [[String: Any]]
        books[0]["futureRating"] = 9.5
        books[0]["contentFlags"] = ["ai_enhanced", "audio_available"]
        obj["books"] = books
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 3)
    }

    @Test("null optional fields (cover) → nil, decode succeeds")
    func nullOptionalCover() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("catalog")) as! [String: Any]
        var books = obj["books"] as! [[String: Any]]
        books[0]["cover"] = NSNull()
        obj["books"] = books
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books[0].cover == nil)
    }

    @Test("one completely corrupt book element is dropped; 2 others survive")
    func corruptElementDropped() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("catalog")) as! [String: Any]
        var books = obj["books"] as! [Any]
        books[1] = NSNull()  // corrupt the second book
        obj["books"] = books
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 2)
    }
}

// MARK: - book_state.json mutations

@Suite("book_state.json — server evolution mutations")
struct BookStateFixtureEvolutionTests {

    @Test("unknown applicationState value → .unknown case, decode succeeds")
    func unknownApplicationState() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("book_state")) as! [String: Any]
        var states = obj["applicationStates"] as! [String: Any]
        states["ch-ah-3"] = "reviewed"
        obj["applicationStates"] = states
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(BookStateResponseEnvelope.self, from: data)
        #expect(response.applicationStates?["ch-ah-3"] == .unknown("reviewed"))
        #expect(response.applicationStates?["ch-ah-1"] == .applied)
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("book_state")) as! [String: Any]
        obj["futureField"] = "value"
        var state = obj["state"] as! [String: Any]
        state["readingVelocity"] = 250
        obj["state"] = state
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(BookStateResponseEnvelope.self, from: data)
        #expect(!response.state.completedChapterIds.isEmpty)
    }
}

// MARK: - entitlement_free.json mutations

@Suite("entitlement_free.json — server evolution mutations")
struct EntitlementFreeEvolutionTests {

    @Test("unknown plan value → .unknown case, decode succeeds")
    func unknownPlan() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("entitlement_free")) as! [String: Any]
        var ent = obj["entitlement"] as! [String: Any]
        ent["plan"] = "TRIAL"
        obj["entitlement"] = ent
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(response.entitlement.plan == .unknown("TRIAL"))
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("entitlement_free")) as! [String: Any]
        var ent = obj["entitlement"] as! [String: Any]
        ent["maxDevices"] = 5
        ent["featureFlags"] = ["offline_mode", "audio"]
        obj["entitlement"] = ent
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(response.entitlement.plan == .free)
    }

    @Test("null optional fields → nil, decode succeeds")
    func nullOptionals() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("entitlement_free")) as! [String: Any]
        var ent = obj["entitlement"] as! [String: Any]
        ent["licenseKey"] = NSNull()
        ent["licenseExpiresAt"] = NSNull()
        obj["entitlement"] = ent
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(response.entitlement.licenseKey == nil)
    }
}

// MARK: - entitlement_pro.json mutations

@Suite("entitlement_pro.json — server evolution mutations")
struct EntitlementProEvolutionTests {

    @Test("extra future fields on PRO entitlement → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("entitlement_pro")) as! [String: Any]
        var ent = obj["entitlement"] as! [String: Any]
        ent["teamId"] = "team-abc"
        obj["entitlement"] = ent
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(response.entitlement.plan == .pro)
    }
}

// MARK: - notifications.json mutations

@Suite("notifications.json — server evolution mutations")
struct NotificationsFixtureEvolutionTests {

    @Test("unknown notification type → .unknown case; notification survives")
    func unknownType() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notifications")) as! [String: Any]
        var notifs = obj["notifications"] as! [[String: Any]]
        notifs[0]["type"] = "book_completed"
        obj["notifications"] = notifs
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 4)
        #expect(response.notifications[0].type == .unknown("book_completed"))
    }

    @Test("corrupt notification element (null) is dropped; 3 others survive")
    func corruptElementDropped() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notifications")) as! [String: Any]
        var notifs = obj["notifications"] as! [Any]
        notifs[2] = NSNull()
        obj["notifications"] = notifs
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 3)
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notifications")) as! [String: Any]
        var notifs = obj["notifications"] as! [[String: Any]]
        notifs[0]["priority"] = "high"
        notifs[0]["expiresAt"] = "2024-02-01T00:00:00Z"
        obj["notifications"] = notifs
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 4)
    }
}

// MARK: - notebook.json mutations

@Suite("notebook.json — server evolution mutations")
struct NotebookFixtureEvolutionTests {

    @Test("unknown entry type → .unknown case; entry survives")
    func unknownEntryType() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notebook")) as! [String: Any]
        var entries = obj["entries"] as! [[String: Any]]
        entries[0]["type"] = "annotation"
        obj["entries"] = entries
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotebookResponse.self, from: data)
        #expect(response.entries.count == 5)
        #expect(response.entries[0].type == .unknown("annotation"))
    }

    @Test("corrupt entry element (null) is dropped; 4 others survive")
    func corruptElementDropped() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notebook")) as! [String: Any]
        var entries = obj["entries"] as! [Any]
        entries[3] = NSNull()
        obj["entries"] = entries
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotebookResponse.self, from: data)
        #expect(response.entries.count == 4)
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("notebook")) as! [String: Any]
        var entries = obj["entries"] as! [[String: Any]]
        entries[0]["aiSummary"] = "AI-generated insight"
        entries[0]["tags"] = ["productivity"]
        obj["entries"] = entries
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(NotebookResponse.self, from: data)
        #expect(response.entries.count == 5)
    }
}

// MARK: - reviews.json mutations

@Suite("reviews.json — server evolution mutations")
struct ReviewsFixtureEvolutionTests {

    @Test("unknown card state → .unknown case; card survives")
    func unknownCardState() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("reviews")) as! [String: Any]
        var cards = obj["cards"] as! [[String: Any]]
        cards[0]["state"] = "suspended"
        obj["cards"] = cards
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ReviewsResponse.self, from: data)
        #expect(response.cards.count == 3)
        #expect(response.cards[0].state == .unknown("suspended"))
    }

    @Test("corrupt card element (null) is dropped; 2 others survive")
    func corruptElementDropped() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("reviews")) as! [String: Any]
        var cards = obj["cards"] as! [Any]
        cards[1] = NSNull()
        obj["cards"] = cards
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ReviewsResponse.self, from: data)
        #expect(response.cards.count == 2)
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("reviews")) as! [String: Any]
        var cards = obj["cards"] as! [[String: Any]]
        cards[0]["retrievability"] = 0.92
        cards[0]["nextInterval"] = 7
        obj["cards"] = cards
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ReviewsResponse.self, from: data)
        #expect(response.cards.count == 3)
    }
}

// MARK: - badges.json mutations

@Suite("badges.json — server evolution mutations")
struct BadgesFixtureEvolutionTests {

    @Test("corrupt badge element (null) is dropped; 3 others survive")
    func corruptElementDropped() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("badges")) as! [String: Any]
        var badges = obj["badges"] as! [Any]
        badges[0] = NSNull()
        obj["badges"] = badges
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(BadgesResponse.self, from: data)
        #expect(response.badges.count == 3)
    }

    @Test("extra future fields on badge → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("badges")) as! [String: Any]
        var badges = obj["badges"] as! [[String: Any]]
        badges[0]["rarity"] = "legendary"
        badges[0]["xpReward"] = 500
        obj["badges"] = badges
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(BadgesResponse.self, from: data)
        #expect(response.badges.count == 4)
    }
}

// MARK: - chapter_emh.json mutations

@Suite("chapter_emh.json — server evolution mutations")
struct ChapterEMHFixtureEvolutionTests {

    @Test("unknown activeVariant → .unknown case; chapter still decodes")
    func unknownActiveVariant() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("chapter_emh")) as! [String: Any]
        var chapter = obj["chapter"] as! [String: Any]
        chapter["activeVariant"] = "ultra"
        obj["chapter"] = chapter
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        #expect(response.chapter.activeVariant == .unknown("ultra"))
    }

    @Test("unknown tone in quiz session → .unknown; chapter decodes fine")
    func unknownAvailableVariant() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("chapter_emh")) as! [String: Any]
        var chapter = obj["chapter"] as! [String: Any]
        var variants = chapter["availableVariants"] as! [Any]
        variants.append("ultra")
        chapter["availableVariants"] = variants
        obj["chapter"] = chapter
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        // known 3 + 1 unknown = 4
        #expect(response.chapter.availableVariants.count == 4)
        #expect(response.chapter.availableVariants.last == .unknown("ultra"))
        // typedContentVariants drops unknown keys — stays at 3
        #expect(response.chapter.typedContentVariants.count == 3)
    }

    @Test("extra future chapter fields → silently ignored")
    func extraChapterFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("chapter_emh")) as! [String: Any]
        var chapter = obj["chapter"] as! [String: Any]
        chapter["audioUrl"] = "https://cdn.example.com/audio/ch1.mp3"
        chapter["videoSummaryUrl"] = NSNull()
        obj["chapter"] = chapter
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        #expect(response.chapter.chapterId == "ch-ah-1")
    }
}

// MARK: - quiz.json mutations

@Suite("quiz.json — server evolution mutations")
struct QuizFixtureEvolutionTests {

    @Test("unknown tone in quiz session → .unknown; quiz decodes fine")
    func unknownTone() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("quiz")) as! [String: Any]
        var quiz = obj["quiz"] as! [String: Any]
        quiz["tone"] = "mentor"
        obj["quiz"] = quiz
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: data)
        #expect(response.quiz.tone == .unknown("mentor"))
    }

    @Test("extra future fields → silently ignored")
    func extraFields() throws {
        var obj = try JSONSerialization.jsonObject(with: try fixtureData("quiz")) as! [String: Any]
        obj["aiHints"] = true
        obj["adaptiveDifficulty"] = "enabled"
        let data = try JSONSerialization.data(withJSONObject: obj)

        let response = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: data)
        #expect(response.quiz.questions.count == 3)
    }
}
