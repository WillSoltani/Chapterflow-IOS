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

// MARK: - BookStateStatus tolerance

@Suite("BookStateStatus server evolution")
struct BookStateStatusEvolutionTests {
    private let state = #"{"currentChapterId":"ch-1","completedChapterIds":[],"unlockedChapterIds":["ch-1"],"chapterScores":{},"chapterCompletedAt":{},"lastReadChapterId":null,"lastOpenedAt":null}"#

    @Test("known statuses decode exactly", arguments: [
        ("started", BookStateStatus.started),
        ("not_started", BookStateStatus.notStarted),
    ])
    func knownStatus(raw: String, expected: BookStateStatus) throws {
        let data = json(#"{"stateStatus":"\#(raw)","state":\#(state),"applicationStates":{}}"#)
        let response = try JSONDecoder.chapterFlow.decode(BookStateGetResponse.self, from: data)
        #expect(response.stateStatus == expected)
    }

    @Test("unknown status is preserved rather than guessed")
    func unknownStatus() throws {
        let data = json(#"{"stateStatus":"paused","state":\#(state),"applicationStates":{}}"#)
        let response = try JSONDecoder.chapterFlow.decode(BookStateGetResponse.self, from: data)
        #expect(response.stateStatus == .unknown("paused"))
    }

    @Test("missing additive status remains compatibility-unknown")
    func missingStatus() throws {
        let data = json(#"{"state":\#(state),"applicationStates":{}}"#)
        let response = try JSONDecoder.chapterFlow.decode(BookStateGetResponse.self, from: data)
        #expect(response.stateStatus == nil)
    }

    @Test("allCases includes only known statuses")
    func allCasesKnownOnly() {
        #expect(BookStateStatus.allCases == [.started, .notStarted])
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

    @Test("element missing the identity field is dropped; rest survive")
    func missingIdentityDropped() throws {
        // Post-reconciliation, `bookId` (or its wire alias `id`) is the ONLY
        // required field — an element without any identity is dropped.
        let bad = #"{"title":"No identity"}"#
        let data = json(#"{"books":[\#(goodBook),\#(bad),\#(goodBook)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 2)
        #expect(response.books.allSatisfy { $0.bookId == "b1" })
    }

    @Test("element with ONLY an identity field survives with defaults (partial data ≠ dropped)")
    func partialElementSurvives() throws {
        let partial = #"{"bookId":"b-partial"}"#
        let data = json(#"{"books":[\#(goodBook),\#(partial)]}"#)
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 2)
        let partialBook = try #require(response.books.first { $0.bookId == "b-partial" })
        #expect(partialBook.title.isEmpty)
        #expect(partialBook.status == nil)
        #expect(partialBook.latestVersion == nil)
        #expect(partialBook.updatedAt == nil)
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

// MARK: - FlowLedgerEntryType tolerance

@Suite("FlowLedgerEntryType server evolution")
struct FlowLedgerEntryTypeEvolutionTests {

    private func entry(type typeStr: String) -> Data {
        Data(#"{"id":"e1","type":"\#(typeStr)","amount":50,"description":"Test","createdAt":"2024-01-01T00:00:00Z"}"#.utf8)
    }

    @Test("unknown type decodes to .unknown, not throws")
    func unknownType() throws {
        let e = try JSONDecoder.chapterFlow.decode(FlowLedgerEntry.self, from: entry(type: "bonus_multiplier"))
        #expect(e.type == .unknown("bonus_multiplier"))
    }

    @Test("known type earn_daily decodes correctly")
    func knownEarnDaily() throws {
        let e = try JSONDecoder.chapterFlow.decode(FlowLedgerEntry.self, from: entry(type: "earn_daily"))
        #expect(e.type == .earnDaily)
    }

    @Test("known type redeem decodes correctly")
    func knownRedeem() throws {
        let e = try JSONDecoder.chapterFlow.decode(FlowLedgerEntry.self, from: entry(type: "redeem"))
        #expect(e.type == .redeem)
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        let hasUnknown = FlowLedgerEntryType.allCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
        #expect(FlowLedgerEntryType.allCases.count == 6)
    }
}

// MARK: - ShopItemKind tolerance

@Suite("ShopItemKind server evolution")
struct ShopItemKindEvolutionTests {

    private func item(kind kindStr: String) -> Data {
        Data(#"{"id":"i1","kind":"\#(kindStr)","name":"Test","description":"Desc","cost":100,"isOwned":false,"isEquipped":null,"previewColor":null}"#.utf8)
    }

    @Test("unknown kind decodes to .unknown, not throws")
    func unknownKind() throws {
        let i = try JSONDecoder.chapterFlow.decode(ShopItem.self, from: item(kind: "avatar_border"))
        #expect(i.kind == .unknown("avatar_border"))
    }

    @Test("unknown kind isCosmetic returns false (safe fallback)")
    func unknownIsCosmetic() {
        #expect(ShopItemKind.unknown("x").isCosmetic == false)
    }

    @Test("known kinds decode correctly")
    func knownKinds() throws {
        let bonus = try JSONDecoder.chapterFlow.decode(ShopItem.self, from: item(kind: "bonus_book_unlock"))
        #expect(bonus.kind == .bonusBookUnlock)
        #expect(bonus.kind.isCosmetic == false)

        let theme = try JSONDecoder.chapterFlow.decode(ShopItem.self, from: item(kind: "theme"))
        #expect(theme.kind == .theme)
        #expect(theme.kind.isCosmetic == true)
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        let hasUnknown = ShopItemKind.allCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
        #expect(ShopItemKind.allCases.count == 6)
    }
}

// MARK: - FlowPointsResponse tolerant decoding

@Suite("FlowPointsResponse tolerant decoding")
struct FlowPointsResponseTests {

    @Test("balance-only response decodes (ledger absent)")
    func balanceOnly() throws {
        let data = Data(#"{"balance":1250}"#.utf8)
        let resp = try JSONDecoder.chapterFlow.decode(FlowPointsResponse.self, from: data)
        #expect(resp.balance == 1250)
        #expect(resp.ledger == nil)
        #expect(resp.equippedCosmetics == nil)
    }

    @Test("response with ledger decodes lossily")
    func withLedger() throws {
        let data = Data(#"""
        {
            "balance": 800,
            "ledger": [
                {"id":"e1","type":"earn_daily","amount":50,"description":"Daily","createdAt":"2024-01-01T00:00:00Z"},
                null,
                {"id":"e2","type":"redeem","amount":-100,"description":"Shop","createdAt":"2024-01-02T00:00:00Z"}
            ]
        }
        """#.utf8)
        let resp = try JSONDecoder.chapterFlow.decode(FlowPointsResponse.self, from: data)
        #expect(resp.balance == 800)
        // null element dropped; 2 valid entries survive
        #expect(resp.ledger?.count == 2)
    }

    @Test("unknown ledger entry type survives lossy decode")
    func unknownLedgerEntryType() throws {
        let data = Data(#"""
        {
            "balance": 500,
            "ledger": [
                {"id":"e1","type":"future_bonus","amount":200,"description":"New event","createdAt":"2024-01-01T00:00:00Z"}
            ]
        }
        """#.utf8)
        let resp = try JSONDecoder.chapterFlow.decode(FlowPointsResponse.self, from: data)
        #expect(resp.ledger?.count == 1)
        #expect(resp.ledger?.first?.type == .unknown("future_bonus"))
    }
}

// MARK: - ShopResponse lossy decoding

@Suite("ShopResponse lossy decoding")
struct ShopResponseLossyTests {

    private let goodItem = #"{"id":"i1","kind":"theme","name":"Dark","description":"Dark theme","cost":500,"isOwned":false,"isEquipped":null,"previewColor":null}"#

    @Test("null element in items is dropped; rest survive")
    func nullItemDropped() throws {
        let data = Data(#"{"items":[\#(goodItem),null,\#(goodItem)]}"#.utf8)
        let resp = try JSONDecoder.chapterFlow.decode(ShopResponse.self, from: data)
        #expect(resp.items.count == 2)
    }

    @Test("item with unknown kind survives in the list")
    func unknownKindSurvives() throws {
        let futureItem = #"{"id":"i2","kind":"holographic_skin","name":"Holo","description":"Future","cost":999,"isOwned":false,"isEquipped":null,"previewColor":null}"#
        let data = Data(#"{"items":[\#(goodItem),\#(futureItem)]}"#.utf8)
        let resp = try JSONDecoder.chapterFlow.decode(ShopResponse.self, from: data)
        #expect(resp.items.count == 2)
        #expect(resp.items[1].kind == .unknown("holographic_skin"))
    }
}

// MARK: - TierKey tolerance

@Suite("TierKey server evolution")
struct TierKeyEvolutionTests {

    @Test("known tiers decode correctly from JSON")
    func knownTiersDecodeCorrectly() throws {
        let data = json(#"["reader","analyst","synthesizer","polymath","luminary"]"#)
        let tiers = try JSONDecoder.chapterFlow.decode([TierKey].self, from: data)
        #expect(tiers.count == 5)
        #expect(tiers[0] == .reader)
        #expect(tiers[1] == .analyst)
        #expect(tiers[2] == .synthesizer)
        #expect(tiers[3] == .polymath)
        #expect(tiers[4] == .luminary)
    }

    @Test("unknown tier decodes to .unknown, not throws")
    func unknownTierDecodesGracefully() throws {
        let data = json(#"["analyst","oracle","luminary"]"#)
        let tiers = try JSONDecoder.chapterFlow.decode([TierKey].self, from: data)
        #expect(tiers.count == 3)
        #expect(tiers[0] == .analyst)
        #expect(tiers[1] == .unknown("oracle"))
        #expect(tiers[2] == .luminary)
    }

    @Test("unknown TierKey round-trips through rawValue")
    func unknownRawValue() {
        let key = TierKey(rawValue: "sage")
        #expect(key == .unknown("sage"))
        #expect(key.rawValue == "sage")
    }

    @Test("allCases excludes .unknown")
    func allCasesKnownOnly() {
        let hasUnknown = TierKey.allCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
        #expect(TierKey.allCases.count == 5)
    }

    @Test("TierResponse with unknown tier decodes without crashing")
    func tierResponseWithUnknownTierDecodes() throws {
        let data = json(#"{"tier":{"currentTier":"oracle","nextTier":null,"overallProgress":0.9,"recentlyPromoted":false,"previousTier":null}}"#)
        let resp = try JSONDecoder.chapterFlow.decode(TierResponse.self, from: data)
        if case .unknown(let raw) = resp.tier.currentTier {
            #expect(raw == "oracle")
        } else {
            Issue.record("Expected .unknown tier from unrecognised tier name")
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
