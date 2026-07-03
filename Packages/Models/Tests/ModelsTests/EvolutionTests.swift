import Testing
import Foundation
@testable import Models

// MARK: - Helpers

private func json(_ string: String) -> Data {
    Data(string.utf8)
}

private func mutate(_ data: Data, transform: (inout [String: Any]) -> Void) throws -> Data {
    var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    transform(&obj)
    return try JSONSerialization.data(withJSONObject: obj)
}

// MARK: - VariantKey tolerance

@Suite("VariantKey server evolution")
struct VariantKeyEvolutionTests {

    @Test("unknown raw value decodes to .unknown, not throws")
    func unknownVariantKey() throws {
        let data = json(#"["easy","future_depth","hard"]"#)
        let keys = try JSONDecoder.chapterFlow.decode([VariantKey].self, from: data)
        #expect(keys.count == 3)
        #expect(keys[0] == .easy)
        #expect(keys[1] == .unknown("future_depth"))
        #expect(keys[2] == .hard)
    }

    @Test("unknown VariantKey round-trips through rawValue")
    func unknownRawValue() {
        let key = VariantKey(rawValue: "future_depth")
        #expect(key == .unknown("future_depth"))
        #expect(key.rawValue == "future_depth")
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        #expect(!VariantKey.allCases.contains { if case .unknown = $0 { return true }; return false })
        #expect(VariantKey.allCases.count == 6)
    }
}

// MARK: - ToneKey tolerance

@Suite("ToneKey server evolution")
struct ToneKeyEvolutionTests {

    @Test("unknown raw value decodes to .unknown, not throws")
    func unknownToneKey() throws {
        let data = json(#"{"tone":"mentor"}"#)
        struct ToneWrapper: Decodable { let tone: ToneKey }
        let w = try JSONDecoder.chapterFlow.decode(ToneWrapper.self, from: data)
        #expect(w.tone == .unknown("mentor"))
    }

    @Test("ToneKeyed.resolve falls back to gentle for unknown tone")
    func unknownToneResolvesToGentle() {
        let tk = ToneKeyed(gentle: "g", direct: "d", competitive: "c")
        #expect(tk.resolve(.unknown("mentor")) == "g")
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        #expect(ToneKey.allCases == [.gentle, .direct, .competitive])
    }
}

// MARK: - VariantFamily tolerance

@Suite("VariantFamily server evolution")
struct VariantFamilyEvolutionTests {

    @Test("unknown raw value decodes to .unknown, not throws")
    func unknownVariantFamily() throws {
        let data = json(#"{"variantFamily":"XYZ","bookId":"b1","title":"T","author":"A","categories":[],"tags":[],"cover":null,"status":"published","latestVersion":1,"currentPublishedVersion":null,"updatedAt":"2024-01-01T00:00:00Z"}"#)
        let item = try JSONDecoder.chapterFlow.decode(BookCatalogItem.self, from: data)
        #expect(item.variantFamily == .unknown("XYZ"))
    }

    @Test("unknown family variantKeys returns empty array")
    func unknownFamilyVariantKeys() {
        #expect(VariantFamily.unknown("XYZ").variantKeys.isEmpty)
    }

    @Test("unknown family defaultVariant returns .medium as safe fallback")
    func unknownFamilyDefaultVariant() {
        #expect(VariantFamily.unknown("XYZ").defaultVariant == .medium)
    }
}

// MARK: - NotebookEntryType tolerance

@Suite("NotebookEntryType server evolution")
struct NotebookEntryTypeEvolutionTests {

    @Test("unknown type decodes to .unknown, not throws")
    func unknownEntryType() throws {
        let data = json(#"{"entryId":"x","bookId":"b","chapterId":null,"type":"annotation","content":null,"quote":null,"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}"#)
        let entry = try JSONDecoder.chapterFlow.decode(NotebookEntry.self, from: data)
        #expect(entry.type == .unknown("annotation"))
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        let known: Set<String> = ["note", "reflection", "bookmark", "commitment", "highlight"]
        #expect(Set(NotebookEntryType.allCases.map(\.rawValue)) == known)
    }
}

// MARK: - FsrsCardState tolerance

@Suite("FsrsCardState server evolution")
struct FsrsCardStateEvolutionTests {

    @Test("unknown state decodes to .unknown, not throws")
    func unknownCardState() throws {
        let data = json(#"{"cardId":"c1","bookId":"b1","chapterId":null,"front":"Q","back":"A","dueAt":null,"stability":null,"difficulty":null,"state":"suspended"}"#)
        let card = try JSONDecoder.chapterFlow.decode(FsrsCard.self, from: data)
        #expect(card.state == .unknown("suspended"))
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        #expect(FsrsCardState.allCases == [.new, .learning, .due, .relearning])
    }
}

// MARK: - ChapterApplicationState tolerance

@Suite("ChapterApplicationState server evolution")
struct ChapterApplicationStateEvolutionTests {

    @Test("unknown state decodes to .unknown, not throws")
    func unknownAppState() throws {
        let data = json(#"{"state":{"currentChapterId":null,"completedChapterIds":[],"unlockedChapterIds":[],"chapterScores":{},"chapterCompletedAt":{},"lastReadChapterId":null,"lastOpenedAt":null},"applicationStates":{"ch-1":"reviewed","ch-2":"applied"}}"#)
        let resp = try JSONDecoder.chapterFlow.decode(BookStateResponseEnvelope.self, from: data)
        #expect(resp.applicationStates?["ch-1"] == .unknown("reviewed"))
        #expect(resp.applicationStates?["ch-2"] == .applied)
    }
}

// MARK: - Entitlement.Plan tolerance

@Suite("Entitlement.Plan server evolution")
struct EntitlementPlanEvolutionTests {

    @Test("unknown plan decodes to .unknown, not throws")
    func unknownPlan() throws {
        let data = json(#"{"plan":"ENTERPRISE","proStatus":null,"proSource":null,"freeBookSlots":0,"unlockedBookIds":[],"unlockedBooksCount":0,"remainingFreeStarts":0,"currentPeriodEnd":null,"cancelAtPeriodEnd":null,"licenseKey":null,"licenseExpiresAt":null}"#)
        let ent = try JSONDecoder.chapterFlow.decode(Entitlement.self, from: data)
        #expect(ent.plan == .unknown("ENTERPRISE"))
    }
}

// MARK: - NotificationKind tolerance

@Suite("NotificationKind server evolution")
struct NotificationKindEvolutionTests {

    @Test("unknown type decodes to .unknown, not throws")
    func unknownKind() throws {
        let data = json(#"{"notificationId":"n1","type":"book_completed","title":"T","body":"B","isRead":false,"createdAt":"2024-01-01T00:00:00Z","deepLink":null}"#)
        let notif = try JSONDecoder.chapterFlow.decode(AppNotification.self, from: data)
        #expect(notif.type == .unknown("book_completed"))
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        #expect(NotificationKind.allCases.count == 4)
    }
}

// MARK: - Lossy CatalogResponse

@Suite("CatalogResponse lossy decoding")
struct CatalogLossyTests {

    private let goodBook = #"{"bookId":"b1","title":"A","author":"X","categories":[],"tags":[],"cover":null,"variantFamily":"EMH","status":"published","latestVersion":1,"currentPublishedVersion":null,"updatedAt":"2024-01-01T00:00:00Z"}"#

    @Test("null element is dropped; rest of catalog survives")
    func nullElementDropped() throws {
        let data = json(#"{"books":[\#(goodBook),null,\#(goodBook)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 2)
    }

    @Test("element missing required field is dropped; rest survive")
    func missingFieldDropped() throws {
        let bad = #"{"bookId":"b-bad"}"# // missing required fields
        let data = json(#"{"books":[\#(goodBook),\#(bad),\#(goodBook)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 2)
        #expect(response.books.allSatisfy { $0.bookId == "b1" })
    }

    @Test("extra future fields are silently ignored")
    func extraFieldsIgnored() throws {
        let withExtra = #"{"bookId":"b1","title":"A","author":"X","categories":[],"tags":[],"cover":null,"variantFamily":"EMH","status":"published","latestVersion":1,"currentPublishedVersion":null,"updatedAt":"2024-01-01T00:00:00Z","futureField":"value","anotherNew":42}"#
        let data = json(#"{"books":[\#(withExtra)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 1)
        #expect(response.books[0].bookId == "b1")
    }
}

// MARK: - Lossy NotebookResponse

@Suite("NotebookResponse lossy decoding")
struct NotebookLossyTests {

    @Test("null element in entries is dropped; rest survive")
    func nullEntryDropped() throws {
        let good = #"{"entryId":"ne-1","bookId":"b1","chapterId":null,"type":"note","content":"text","quote":null,"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}"#
        let data = json(#"{"entries":[\#(good),null,\#(good)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(NotebookResponse.self, from: data)
        #expect(response.entries.count == 2)
    }
}

// MARK: - Lossy ReviewsResponse

@Suite("ReviewsResponse lossy decoding")
struct ReviewsLossyTests {

    @Test("null element in cards is dropped; rest survive")
    func nullCardDropped() throws {
        let good = #"{"cardId":"c1","bookId":"b1","chapterId":null,"front":"Q","back":"A","dueAt":null,"stability":null,"difficulty":null,"state":"due"}"#
        let data = json(#"{"cards":[\#(good),null,\#(good)],"dueCount":2}"#)
        let response = try JSONDecoder.chapterFlow.decode(ReviewsResponse.self, from: data)
        #expect(response.cards.count == 2)
        #expect(response.dueCount == 2)
    }
}

// MARK: - Lossy BadgesResponse

@Suite("BadgesResponse lossy decoding")
struct BadgesLossyTests {

    @Test("null element in badges is dropped; rest survive")
    func nullBadgeDropped() throws {
        let good = #"{"badgeId":"bg-1","name":"First Chapter","description":"Read your first chapter","category":"reading","isEarned":true,"earnedAt":"2024-01-01T00:00:00Z","icon":"📖"}"#
        let data = json(#"{"badges":[\#(good),null,\#(good)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(BadgesResponse.self, from: data)
        #expect(response.badges.count == 2)
    }
}

// MARK: - Lossy NotificationsResponse

@Suite("NotificationsResponse lossy decoding")
struct NotificationsLossyTests {

    @Test("null element in notifications is dropped; rest survive")
    func nullNotifDropped() throws {
        let good = #"{"notificationId":"n1","type":"quiz_unlocked","title":"T","body":"B","isRead":false,"createdAt":"2024-01-01T00:00:00Z","deepLink":null}"#
        let data = json(#"{"notifications":[\#(good),null,\#(good)],"unreadCount":2}"#)
        let response = try JSONDecoder.chapterFlow.decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 2)
        #expect(response.unreadCount == 2)
    }
}

// MARK: - EdgeType tolerance

@Suite("EdgeType server evolution")
struct EdgeTypeEvolutionTests {

    @Test("known prerequisite type decodes correctly")
    func knownPrerequisite() throws {
        let data = json(#"{"from":"a","to":"b","type":"prerequisite"}"#)
        let edge = try JSONDecoder.chapterFlow.decode(ConceptEdge.self, from: data)
        #expect(edge.edgeType == .prerequisite)
        #expect(edge.from == "a")
        #expect(edge.to == "b")
    }

    @Test("unknown edge type decodes to .unknown, not throws")
    func unknownEdgeType() throws {
        let data = json(#"{"from":"a","to":"b","type":"related_concept"}"#)
        let edge = try JSONDecoder.chapterFlow.decode(ConceptEdge.self, from: data)
        #expect(edge.edgeType == .unknown("related_concept"))
    }

    @Test("array of edges with mixed known/unknown types all survive")
    func mixedEdgeTypes() throws {
        let data = json(#"[{"from":"a","to":"b","type":"prerequisite"},{"from":"b","to":"c","type":"future_type"},{"from":"c","to":"d","type":"prerequisite"}]"#)
        let edges = try JSONDecoder.chapterFlow.decode([ConceptEdge].self, from: data)
        #expect(edges.count == 3)
        #expect(edges[0].edgeType == .prerequisite)
        #expect(edges[1].edgeType == .unknown("future_type"))
        #expect(edges[2].edgeType == .prerequisite)
    }

    @Test("ConceptGraph with unknown edge type decodes without crashing")
    func conceptGraphWithUnknownEdge() throws {
        let data = json(#"{"concepts":[{"id":"c1","label":"Habit Loop","introducedIn":"ch1","summary":"The loop."}],"edges":[{"from":"c1","to":"c2","type":"associates_with"}],"chapterIntroduces":null,"chapterRequires":null}"#)
        let graph = try JSONDecoder.chapterFlow.decode(ConceptGraph.self, from: data)
        #expect(graph.concepts.count == 1)
        #expect(graph.edges.count == 1)
        if case .unknown(let raw) = graph.edges[0].edgeType {
            #expect(raw == "associates_with")
        } else {
            Issue.record("Expected .unknown edge type")
        }
    }
}

// MARK: - ISO-8601 date tolerance

@Suite("Date decoding tolerance")
struct DateDecodingTests {

    @Test("ISO-8601 with fractional seconds decodes")
    func withFractionalSeconds() throws {
        let data = json(#"{"notificationId":"n1","type":"quiz_unlocked","title":"T","body":"B","isRead":false,"createdAt":"2024-01-16T09:00:00.000Z","deepLink":null}"#)
        let notif = try JSONDecoder.chapterFlow.decode(AppNotification.self, from: data)
        #expect(!notif.notificationId.isEmpty)
    }

    @Test("ISO-8601 without fractional seconds decodes")
    func withoutFractionalSeconds() throws {
        let data = json(#"{"notificationId":"n1","type":"quiz_unlocked","title":"T","body":"B","isRead":false,"createdAt":"2024-01-16T09:00:00Z","deepLink":null}"#)
        let notif = try JSONDecoder.chapterFlow.decode(AppNotification.self, from: data)
        #expect(!notif.notificationId.isEmpty)
    }
}
