import Testing
import Foundation
@testable import Models

// MARK: - Helpers

private let resolver = ChapterContentResolver()

/// Builds a minimal Chapter for resolver tests.
private func makeChapter(
    availableVariants: [VariantKey] = [.easy, .medium, .hard],
    activeVariant: VariantKey = .medium,
    contentVariants: [String: ChapterVariantContent] = [:],
    examples: [Example] = [],
    implementationPlan: ImplementationPlan? = nil,
    reviewCards: [ReviewCard]? = nil,
    keyTakeawayCard: ToneKeyed? = nil,
    v21Extras: V21ChapterExtras? = nil
) -> Chapter {
    // Build a default content for `activeVariant` from contentVariants if present
    let defaultContent = contentVariants[activeVariant.rawValue] ?? ChapterVariantContent(
        chapterBreakdown: ToneKeyed(gentle: "G breakdown", direct: "D breakdown", competitive: "C breakdown"),
        keyTakeaways: nil,
        oneMinuteRecap: nil,
        activationPrompt: nil,
        selfCheckPrompts: nil,
        reflectionPrompts: nil,
        importantSummary: nil,
        summaryBullets: nil,
        takeaways: nil,
        practice: nil
    )
    return Chapter(
        chapterId: "ch-test-1",
        number: 1,
        title: "Test Chapter",
        readingTimeMinutes: 10,
        activeVariant: activeVariant,
        availableVariants: availableVariants,
        content: defaultContent,
        contentVariants: contentVariants,
        examples: examples,
        implementationPlan: implementationPlan,
        reviewCards: reviewCards,
        keyTakeawayCard: keyTakeawayCard,
        v21Extras: v21Extras
    )
}

private func makeToneKeyed(_ base: String) -> ToneKeyed {
    ToneKeyed(gentle: "\(base)-gentle", direct: "\(base)-direct", competitive: "\(base)-competitive")
}

private func makeContent(breakdown: ToneKeyed? = nil, recap: OneMinuteRecap? = nil) -> ChapterVariantContent {
    ChapterVariantContent(
        chapterBreakdown: breakdown ?? makeToneKeyed("breakdown"),
        keyTakeaways: [
            KeyTakeaway(point: makeToneKeyed("takeaway"), moreDetails: makeToneKeyed("details"))
        ],
        oneMinuteRecap: recap,
        activationPrompt: makeToneKeyed("activation"),
        selfCheckPrompts: [makeToneKeyed("selfcheck")],
        reflectionPrompts: [makeToneKeyed("reflection")],
        importantSummary: "Important summary",
        summaryBullets: ["bullet1", "bullet2"],
        takeaways: ["takeaway1"],
        practice: ["practice1"]
    )
}

// MARK: - Variant selection

@Suite("ChapterContentResolver — variant selection")
struct VariantSelectionTests {
    @Test("uses requested variant when available")
    func usesRequestedVariant() {
        let variants: [String: ChapterVariantContent] = [
            "easy": makeContent(breakdown: makeToneKeyed("easy-bd")),
            "medium": makeContent(breakdown: makeToneKeyed("medium-bd")),
            "hard": makeContent(breakdown: makeToneKeyed("hard-bd"))
        ]
        let chapter = makeChapter(availableVariants: [.easy, .medium, .hard], activeVariant: .medium, contentVariants: variants)
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .hard, selectedTone: .gentle)
        #expect(resolved.resolvedVariant == .hard)
        #expect(resolved.chapterBreakdown == "hard-bd-gentle")
    }

    @Test("falls back to activeVariant when requested variant is unavailable")
    func fallsBackToActiveVariant() {
        let variants: [String: ChapterVariantContent] = [
            "easy": makeContent(breakdown: makeToneKeyed("easy-bd")),
            "medium": makeContent(breakdown: makeToneKeyed("medium-bd"))
        ]
        let chapter = makeChapter(availableVariants: [.easy, .medium], activeVariant: .easy, contentVariants: variants)
        // Request 'hard' which isn't available; should fall back to 'easy' (activeVariant)
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .hard, selectedTone: .direct)
        #expect(resolved.resolvedVariant == .easy)
        #expect(resolved.chapterBreakdown == "easy-bd-direct")
    }

    @Test("falls back to first available variant when neither requested nor active is available")
    func fallsBackToFirstAvailable() {
        let variants: [String: ChapterVariantContent] = [
            "easy": makeContent(breakdown: makeToneKeyed("first-bd"))
        ]
        // activeVariant is medium but it's not in the dict
        let chapter = makeChapter(availableVariants: [.easy], activeVariant: .medium, contentVariants: variants)
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .hard, selectedTone: .direct)
        #expect(resolved.resolvedVariant == .easy)
        #expect(resolved.chapterBreakdown == "first-bd-direct")
    }
}

// MARK: - Tone resolution

@Suite("ChapterContentResolver — tone resolution")
struct ToneResolutionTests {
    @Test("resolves chapterBreakdown for all three tones")
    func breakdownAllTones() {
        let content = makeContent(breakdown: makeToneKeyed("bd"))
        let chapter = makeChapter(
            availableVariants: [.medium],
            activeVariant: .medium,
            contentVariants: ["medium": content]
        )
        for tone in ToneKey.allCases {
            let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: tone)
            #expect(resolved.chapterBreakdown == "bd-\(tone.rawValue)")
            #expect(resolved.resolvedTone == tone)
        }
    }

    @Test("resolves keyTakeaways with moreDetails")
    func keyTakeaways() {
        let chapter = makeChapter(
            availableVariants: [.medium],
            activeVariant: .medium,
            contentVariants: ["medium": makeContent()]
        )
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .direct)
        #expect(resolved.keyTakeaways.count == 1)
        #expect(resolved.keyTakeaways[0].point == "takeaway-direct")
        #expect(resolved.keyTakeaways[0].moreDetails == "details-direct")
    }

    @Test("resolves simple oneMinuteRecap")
    func simpleRecap() {
        let recap = OneMinuteRecap.simple(makeToneKeyed("recap"))
        let content = makeContent(recap: recap)
        let chapter = makeChapter(
            availableVariants: [.medium],
            activeVariant: .medium,
            contentVariants: ["medium": content]
        )
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .competitive)
        let recapResult = try! require(resolved.oneMinuteRecap)
        #expect(recapResult.text == "recap-competitive")
        #expect(recapResult.retrieve == nil)
    }

    @Test("resolves structured oneMinuteRecap")
    func structuredRecap() {
        let recap = OneMinuteRecap.structured(
            retrieve: makeToneKeyed("retrieve"),
            connect: makeToneKeyed("connect"),
            preview: makeToneKeyed("preview")
        )
        let content = makeContent(recap: recap)
        let chapter = makeChapter(
            availableVariants: [.medium],
            activeVariant: .medium,
            contentVariants: ["medium": content]
        )
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .gentle)
        let recapResult = try! require(resolved.oneMinuteRecap)
        #expect(recapResult.text == nil)
        #expect(recapResult.retrieve == "retrieve-gentle")
        #expect(recapResult.connect == "connect-gentle")
        #expect(recapResult.preview == "preview-gentle")
    }

    @Test("resolves selfCheck and reflectionPrompts")
    func multiplePrompts() {
        let chapter = makeChapter(
            availableVariants: [.medium],
            activeVariant: .medium,
            contentVariants: ["medium": makeContent()]
        )
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .direct)
        #expect(resolved.selfCheckPrompts == ["selfcheck-direct"])
        #expect(resolved.reflectionPrompts == ["reflection-direct"])
    }
}

// MARK: - Example resolution

@Suite("ChapterContentResolver — example resolution")
struct ExampleResolutionTests {
    @Test("resolves example with plain string scenario")
    func plainStringScenario() {
        let example = Example(
            exampleId: "e1",
            title: "Test",
            scenario: .string("Plain scenario"),
            whatToDo: .strings(["Step 1", "Step 2"]),
            whyItMatters: .toneKeyed(makeToneKeyed("why")),
            contexts: ["ctx"],
            category: "test"
        )
        let chapter = makeChapter(examples: [example])
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .direct)
        #expect(resolved.examples.count == 1)
        #expect(resolved.examples[0].scenario == "Plain scenario")
        #expect(resolved.examples[0].whatToDo == ["Step 1", "Step 2"])
        #expect(resolved.examples[0].whyItMatters == "why-direct")
    }

    @Test("resolves example with ToneKeyed scenario and StringsOrTone.toneKeyed whatToDo")
    func toneKeyedScenarioAndWhatToDo() {
        let example = Example(
            exampleId: "e2",
            title: nil,
            scenario: .toneKeyed(makeToneKeyed("scenario")),
            whatToDo: .toneKeyed(makeToneKeyed("what")),
            whyItMatters: .string("Plain why"),
            contexts: nil,
            category: nil
        )
        let chapter = makeChapter(examples: [example])
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .competitive)
        let ex = resolved.examples[0]
        #expect(ex.scenario == "scenario-competitive")
        #expect(ex.whatToDo == ["what-competitive"]) // wrapped in array
        #expect(ex.whyItMatters == "Plain why")
        #expect(ex.contexts == [])
    }
}

// MARK: - ImplementationPlan resolution

@Suite("ChapterContentResolver — ImplementationPlan resolution")
struct PlanResolutionTests {
    @Test("resolves all implementation plan fields")
    func fullPlan() {
        let plan = ImplementationPlan(
            coreSkill: makeToneKeyed("skill"),
            concreteAction: makeToneKeyed("action"),
            ifThenPlans: [IfThenPlan(context: "When X", plan: makeToneKeyed("then"))],
            twentyFourHourChallenge: makeToneKeyed("24h"),
            weeklyPractice: makeToneKeyed("weekly"),
            friction: makeToneKeyed("friction"),
            checkpoint: makeToneKeyed("check")
        )
        let chapter = makeChapter(implementationPlan: plan)
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .gentle)
        let rp = try! require(resolved.implementationPlan)
        #expect(rp.coreSkill == "skill-gentle")
        #expect(rp.concreteAction == "action-gentle")
        #expect(rp.ifThenPlans.count == 1)
        #expect(rp.ifThenPlans[0].context == "When X")
        #expect(rp.ifThenPlans[0].plan == "then-gentle")
        #expect(rp.twentyFourHourChallenge == "24h-gentle")
        #expect(rp.weeklyPractice == "weekly-gentle")
        #expect(rp.friction == "friction-gentle")
        #expect(rp.checkpoint == "check-gentle")
    }

    @Test("nil implementationPlan passes through as nil")
    func nilPlan() {
        let chapter = makeChapter(implementationPlan: nil)
        let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: .direct)
        #expect(resolved.implementationPlan == nil)
    }
}

// MARK: - ReviewCard resolution

@Suite("ChapterContentResolver — ReviewCard resolution")
struct ReviewCardResolutionTests {
    @Test("resolves review card front/back per tone")
    func reviewCards() {
        let cards = [
            ReviewCard(cardId: "c1", front: makeToneKeyed("front"), back: makeToneKeyed("back"), difficulty: "easy")
        ]
        let chapter = makeChapter(reviewCards: cards)
        for tone in ToneKey.allCases {
            let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: tone)
            #expect(resolved.reviewCards.count == 1)
            #expect(resolved.reviewCards[0].front == "front-\(tone.rawValue)")
            #expect(resolved.reviewCards[0].back == "back-\(tone.rawValue)")
            #expect(resolved.reviewCards[0].difficulty == "easy")
        }
    }

    @Test("keyTakeawayCard is resolved per tone")
    func keyTakeawayCard() {
        let chapter = makeChapter(keyTakeawayCard: makeToneKeyed("ktc"))
        for tone in ToneKey.allCases {
            let resolved = resolver.resolve(chapter: chapter, selectedVariant: .medium, selectedTone: tone)
            #expect(resolved.keyTakeawayCard == "ktc-\(tone.rawValue)")
        }
    }
}

// MARK: - Round-trip from fixture

@Suite("ChapterContentResolver — fixture round-trip")
struct ResolverFixtureTests {
    @Test("resolves EMH chapter for all variant/tone combos without error")
    func emhAllCombos() throws {
        let data = try fixtureData(named: "chapter_emh")
        let ch = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data).chapter
        for variant in VariantKey.emhKeys {
            for tone in ToneKey.allCases {
                let resolved = resolver.resolve(chapter: ch, selectedVariant: variant, selectedTone: tone)
                #expect(resolved.resolvedTone == tone)
                _ = resolved.resolvedVariant
            }
        }
    }

    @Test("resolves PBC chapter for all variant/tone combos without error")
    func pbcAllCombos() throws {
        let data = try fixtureData(named: "chapter_pbc")
        let ch = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data).chapter
        for variant in VariantKey.pbcKeys {
            for tone in ToneKey.allCases {
                let resolved = resolver.resolve(chapter: ch, selectedVariant: variant, selectedTone: tone)
                #expect(resolved.resolvedTone == tone)
            }
        }
    }

    @Test("v21Extras pass through unmodified")
    func v21ExtrasPassThrough() throws {
        let data = try fixtureData(named: "chapter_emh")
        let ch = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data).chapter
        let resolved = resolver.resolve(chapter: ch, selectedVariant: .medium, selectedTone: .direct)
        #expect(resolved.v21Extras?.hook != nil)
        #expect(resolved.v21Extras?.memorableLines?.count == 2)
    }
}

// MARK: - Helpers

private struct NilUnwrapError: Error {}

private func require<T>(_ value: T?) throws -> T {
    guard let value else {
        Issue.record("Unexpectedly nil")
        throw NilUnwrapError()
    }
    return value
}

private func fixtureData(named name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
        Issue.record("Missing fixture: Resources/\(name).json")
        struct Missing: Error {}
        throw Missing()
    }
    return try Data(contentsOf: url)
}
