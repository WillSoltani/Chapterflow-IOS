import Testing
@testable import ReaderFeature
import Models

@Suite("ReaderContentBuilder")
struct ReaderContentBuilderTests {
    let builder = ReaderContentBuilder()

    // MARK: - Helpers

    func makeChapter(
        title: String = "Test Chapter",
        chapterBreakdown: String? = nil,
        keyTakeaways: [ResolvedKeyTakeaway] = [],
        examples: [ResolvedExample] = [],
        implementationPlan: ResolvedImplementationPlan? = nil,
        oneMinuteRecap: ResolvedOneMinuteRecap? = nil,
        activationPrompt: String? = nil,
        selfCheckPrompts: [String] = [],
        reflectionPrompts: [String] = [],
        v21Extras: V21ChapterExtras? = nil
    ) -> ResolvedChapter {
        ResolvedChapter(
            chapterId: "test-1",
            number: 1,
            title: title,
            readingTimeMinutes: 10,
            chapterBreakdown: chapterBreakdown,
            keyTakeaways: keyTakeaways,
            oneMinuteRecap: oneMinuteRecap,
            activationPrompt: activationPrompt,
            selfCheckPrompts: selfCheckPrompts,
            reflectionPrompts: reflectionPrompts,
            importantSummary: nil,
            summaryBullets: [],
            takeaways: [],
            practice: [],
            examples: examples,
            implementationPlan: implementationPlan,
            v21Extras: v21Extras,
            reviewCards: [],
            keyTakeawayCard: nil,
            resolvedVariant: .medium,
            resolvedTone: .gentle
        )
    }

    func makeExample() -> ResolvedExample {
        ResolvedExample(
            exampleId: nil,
            title: nil,
            scenario: "A test scenario.",
            whatToDo: ["Step 1", "Step 2"],
            whyItMatters: "Because it matters.",
            contexts: [],
            category: nil
        )
    }

    func makeIfThenPlan() -> ResolvedIfThenPlan {
        ResolvedIfThenPlan(context: "When X happens", plan: "Do Y instead.")
    }

    // MARK: - Title block

    @Test("first block is always a chapter-title heading")
    func firstBlockIsChapterTitle() throws {
        let blocks = builder.build(from: makeChapter(title: "My Chapter"))
        let first = try #require(blocks.first)
        guard case .heading(let text, let isChapterTitle) = first else {
            Issue.record("Expected first block to be .heading")
            return
        }
        #expect(text == "My Chapter")
        #expect(isChapterTitle == true)
    }

    @Test("minimal chapter produces exactly one block (the title)")
    func minimalChapterOnlyTitle() {
        let blocks = builder.build(from: makeChapter())
        #expect(blocks.count == 1)
    }

    // MARK: - Paragraph / breakdown

    @Test("non-empty chapterBreakdown emits a paragraph block")
    func breakdownEmitsParagraph() {
        let blocks = builder.build(from: makeChapter(chapterBreakdown: "Some breakdown."))
        let hasParagraph = blocks.contains { if case .paragraph = $0 { return true }; return false }
        #expect(hasParagraph)
    }

    @Test("nil chapterBreakdown emits no paragraph block")
    func nilBreakdownNoParagraph() {
        let blocks = builder.build(from: makeChapter(chapterBreakdown: nil))
        let hasParagraph = blocks.contains { if case .paragraph = $0 { return true }; return false }
        #expect(!hasParagraph)
    }

    @Test("empty chapterBreakdown emits no paragraph block")
    func emptyBreakdownNoParagraph() {
        let blocks = builder.build(from: makeChapter(chapterBreakdown: ""))
        let hasParagraph = blocks.contains { if case .paragraph = $0 { return true }; return false }
        #expect(!hasParagraph)
    }

    // MARK: - Key takeaways

    @Test("two key takeaways emit a section heading + two keyTakeaway blocks")
    func keyTakeawaysEmitBlocks() {
        let kts = [
            ResolvedKeyTakeaway(point: "Point A", moreDetails: nil),
            ResolvedKeyTakeaway(point: "Point B", moreDetails: "Details B"),
        ]
        let blocks = builder.build(from: makeChapter(keyTakeaways: kts))
        let ktBlocks = blocks.filter { if case .keyTakeaway = $0 { return true }; return false }
        #expect(ktBlocks.count == 2)
    }

    @Test("no key takeaways emit no keyTakeaway section heading")
    func noKeyTakeawaysNoHeading() {
        let blocks = builder.build(from: makeChapter(keyTakeaways: []))
        let headings = blocks.compactMap { block -> String? in
            if case .heading(let t, false) = block { return t }; return nil
        }
        #expect(!headings.contains("Key Takeaways"))
    }

    // MARK: - Examples

    @Test("one example emits a section heading + one example block")
    func examplesEmitBlocks() {
        let blocks = builder.build(from: makeChapter(examples: [makeExample()]))
        let exBlocks = blocks.filter { if case .example = $0 { return true }; return false }
        #expect(exBlocks.count == 1)
    }

    // MARK: - Implementation plan

    @Test("if-then plan items emit implementationPlanItem blocks")
    func ifThenPlansEmitBlocks() {
        let plan = ResolvedImplementationPlan(
            coreSkill: nil,
            concreteAction: nil,
            ifThenPlans: [makeIfThenPlan(), makeIfThenPlan()],
            twentyFourHourChallenge: nil,
            weeklyPractice: nil,
            friction: nil,
            checkpoint: nil
        )
        let blocks = builder.build(from: makeChapter(implementationPlan: plan))
        let planItems = blocks.filter { if case .implementationPlanItem = $0 { return true }; return false }
        #expect(planItems.count == 2)
    }

    @Test("24-hour challenge emits a callout block")
    func challengeEmitsCallout() {
        let plan = ResolvedImplementationPlan(
            coreSkill: nil,
            concreteAction: nil,
            ifThenPlans: [],
            twentyFourHourChallenge: "Do it today.",
            weeklyPractice: nil,
            friction: nil,
            checkpoint: nil
        )
        let blocks = builder.build(from: makeChapter(implementationPlan: plan))
        let callouts = blocks.compactMap { block -> String? in
            if case .callout(let t, _) = block { return t }; return nil
        }
        #expect(callouts.contains("24-Hour Challenge"))
    }

    @Test("empty implementation plan emits no plan section")
    func emptyPlanNoSection() {
        let plan = ResolvedImplementationPlan(
            coreSkill: nil,
            concreteAction: nil,
            ifThenPlans: [],
            twentyFourHourChallenge: nil,
            weeklyPractice: nil,
            friction: nil,
            checkpoint: nil
        )
        let blocks = builder.build(from: makeChapter(implementationPlan: plan))
        let headings = blocks.compactMap { block -> String? in
            if case .heading(let t, false) = block { return t }; return nil
        }
        #expect(!headings.contains("Implementation Plan"))
    }

    // MARK: - Recap

    @Test("non-nil oneMinuteRecap emits a recap block")
    func recapBlockEmitted() {
        let recap = ResolvedOneMinuteRecap(text: "A recap.", retrieve: nil, connect: nil, preview: nil)
        let blocks = builder.build(from: makeChapter(oneMinuteRecap: recap))
        let recapBlocks = blocks.filter { if case .recap = $0 { return true }; return false }
        #expect(recapBlocks.count == 1)
    }

    @Test("nil oneMinuteRecap emits no recap block")
    func nilRecapNoBlock() {
        let blocks = builder.build(from: makeChapter(oneMinuteRecap: nil))
        let recapBlocks = blocks.filter { if case .recap = $0 { return true }; return false }
        #expect(recapBlocks.isEmpty)
    }

    // MARK: - v21Extras

    @Test("v21Extras hook emits a callout block with title 'Hook'")
    func hookEmitsCallout() {
        let extras = V21ChapterExtras(
            hook: "Hook text.",
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let callouts = blocks.compactMap { block -> (String, String)? in
            if case .callout(let t, let b) = block { return (t, b) }; return nil
        }
        #expect(callouts.contains { $0.0 == "Hook" && $0.1 == "Hook text." })
    }

    @Test("v21Extras counterintuition emits a callout block")
    func counterintuitionEmitsCallout() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: "Counter text.",
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let titles = blocks.compactMap { block -> String? in
            if case .callout(let t, _) = block { return t }; return nil
        }
        #expect(titles.contains("Counterintuition"))
    }

    @Test("two memorable lines emit two pullQuote blocks")
    func memorableLinesEmitPullQuotes() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: [
                MemorableLine(text: "Quote 1", location: nil, why: nil),
                MemorableLine(text: "Quote 2", location: "p.5", why: nil),
            ],
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let pullQuotes = blocks.filter { if case .pullQuote = $0 { return true }; return false }
        #expect(pullQuotes.count == 2)
    }

    @Test("nil v21Extras emits no pullQuote or v21 callout blocks")
    func nilV21ExtrasNoV21Blocks() {
        let blocks = builder.build(from: makeChapter(v21Extras: nil))
        let pullQuotes = blocks.filter { if case .pullQuote = $0 { return true }; return false }
        #expect(pullQuotes.isEmpty)
        let hookCallout = blocks.first { if case .callout(let t, _) = $0 { return t == "Hook" }; return false }
        #expect(hookCallout == nil)
    }

    // MARK: - Prompts

    @Test("self-check prompts emit bullet blocks")
    func selfCheckEmitsBullets() {
        let blocks = builder.build(from: makeChapter(selfCheckPrompts: ["Q1?", "Q2?"]))
        let headings = blocks.compactMap { block -> String? in
            if case .heading(let t, false) = block { return t }; return nil
        }
        #expect(headings.contains("Self-Check"))
        let bullets = blocks.filter { if case .bullet = $0 { return true }; return false }
        #expect(bullets.count == 2)
    }

    @Test("reflection prompts emit bullet blocks under 'Reflect'")
    func reflectionEmitsBullets() {
        let blocks = builder.build(from: makeChapter(reflectionPrompts: ["R1?", "R2?"]))
        let headings = blocks.compactMap { block -> String? in
            if case .heading(let t, false) = block { return t }; return nil
        }
        #expect(headings.contains("Reflect"))
    }

    // MARK: - Canonical reading order

    @Test("hook appears before chapterBreakdown, breakdown before keyTakeaways, recap after examples")
    func canonicalReadingOrder() throws {
        let extras = V21ChapterExtras(
            hook: "The hook.",
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let kt = ResolvedKeyTakeaway(point: "Point", moreDetails: nil)
        let recap = ResolvedOneMinuteRecap(text: "Recap.", retrieve: nil, connect: nil, preview: nil)
        let blocks = builder.build(from: makeChapter(
            chapterBreakdown: "Breakdown.",
            keyTakeaways: [kt],
            examples: [makeExample()],
            oneMinuteRecap: recap,
            v21Extras: extras
        ))

        let hookIdx = try #require(blocks.firstIndex { if case .callout("Hook", _) = $0 { return true }; return false })
        let paraIdx = try #require(blocks.firstIndex { if case .paragraph = $0 { return true }; return false })
        let ktIdx = try #require(blocks.firstIndex { if case .keyTakeaway = $0 { return true }; return false })
        let exIdx = try #require(blocks.firstIndex { if case .example = $0 { return true }; return false })
        let recapIdx = try #require(blocks.firstIndex { if case .recap = $0 { return true }; return false })

        #expect(hookIdx < paraIdx)
        #expect(paraIdx < ktIdx)
        #expect(ktIdx < exIdx)
        #expect(exIdx < recapIdx)
    }
}
