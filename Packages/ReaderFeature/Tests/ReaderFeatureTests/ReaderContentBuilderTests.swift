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

    @Test("v21Extras hook emits a hookBanner block")
    func hookEmitsBanner() {
        let extras = V21ChapterExtras(
            hook: "Hook text.",
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasHook = blocks.contains { if case .hookBanner(let t) = $0 { return t == "Hook text." }; return false }
        #expect(hasHook)
    }

    @Test("v21Extras counterintuition emits a counterintuitionCallout block")
    func counterintuitionEmitsBlock() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: "Counter text.",
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasCI = blocks.contains {
            if case .counterintuitionCallout(let t) = $0 { return t == "Counter text." }; return false
        }
        #expect(hasCI)
    }

    @Test("v21Extras tryThisNow emits a tryThisNowDirective block")
    func tryThisNowEmitsDirective() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: "Do this now.",
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasTTN = blocks.contains {
            if case .tryThisNowDirective(let t) = $0 { return t == "Do this now." }; return false
        }
        #expect(hasTTN)
    }

    @Test("v21Extras keyTakeaway emits a v21KeyTakeawayCard block")
    func keyTakeawayEmitsCard() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: "The key insight.",
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasKT = blocks.contains {
            if case .v21KeyTakeawayCard(let t) = $0 { return t == "The key insight." }; return false
        }
        #expect(hasKT)
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

    @Test("nil v21Extras emits no pullQuote or premium blocks")
    func nilV21ExtrasNoV21Blocks() {
        let blocks = builder.build(from: makeChapter(v21Extras: nil))
        let pullQuotes = blocks.filter { if case .pullQuote = $0 { return true }; return false }
        #expect(pullQuotes.isEmpty)
        let hasHookBanner = blocks.contains { if case .hookBanner = $0 { return true }; return false }
        #expect(!hasHookBanner)
        let hasCI = blocks.contains { if case .counterintuitionCallout = $0 { return true }; return false }
        #expect(!hasCI)
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

        let hookIdx = try #require(blocks.firstIndex { if case .hookBanner = $0 { return true }; return false })
        let paraIdx = try #require(blocks.firstIndex { if case .paragraph = $0 { return true }; return false })
        let ktIdx = try #require(blocks.firstIndex { if case .keyTakeaway = $0 { return true }; return false })
        let exIdx = try #require(blocks.firstIndex { if case .example = $0 { return true }; return false })
        let recapIdx = try #require(blocks.firstIndex { if case .recap = $0 { return true }; return false })

        #expect(hookIdx < paraIdx)
        #expect(paraIdx < ktIdx)
        #expect(ktIdx < exIdx)
        #expect(exIdx < recapIdx)
    }

    // MARK: - Experience plan

    func makeExperiencePlan(
        failureRecovery: FailureRecovery? = nil,
        transferPrompt: TransferPrompt? = nil,
        behaviorLoop: BehaviorLoop? = nil
    ) -> V21ExperiencePlan {
        V21ExperiencePlan(
            failureRecovery: failureRecovery,
            transferPrompt: transferPrompt,
            behaviorLoop: behaviorLoop
        )
    }

    func makeFullFailureRecovery() -> FailureRecovery {
        FailureRecovery(
            normalizingLine: "It happens.",
            cueQuestion: "Which situation?",
            options: ["Option A", "Option B"],
            repairLine: "Get back on track."
        )
    }

    @Test("experiencePlan failureRecovery emits a failureRecoveryBlock")
    func failureRecoveryEmitsBlock() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: makeExperiencePlan(failureRecovery: makeFullFailureRecovery())
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasRecovery = blocks.contains { if case .failureRecoveryBlock = $0 { return true }; return false }
        #expect(hasRecovery)
    }

    @Test("experiencePlan transferPrompt emits a transferPromptBlock")
    func transferPromptEmitsBlock() {
        let transfer = TransferPrompt(prompt: "Try it here.", contexts: ["Work", "Home"])
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: makeExperiencePlan(transferPrompt: transfer)
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasTransfer = blocks.contains { if case .transferPromptBlock = $0 { return true }; return false }
        #expect(hasTransfer)
    }

    @Test("experiencePlan behaviorLoop emits a behaviorLoopBlock with examples and plans")
    func behaviorLoopEmitsBlock() {
        let pattern = ReaderPattern(id: "p1", label: "The Doer", mapsToPlanIndex: nil, mapsToExampleIndex: 0)
        let loop = BehaviorLoop(readerPatterns: [pattern])
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: makeExperiencePlan(behaviorLoop: loop)
        )
        let chapter = makeChapter(examples: [makeExample()], v21Extras: extras)
        let blocks = builder.build(from: chapter)

        var foundLoop = false
        for block in blocks {
            if case .behaviorLoopBlock(let bl, let exs, _) = block {
                foundLoop = true
                #expect(bl.readerPatterns.count == 1)
                #expect(exs.count == 1)
            }
        }
        #expect(foundLoop)
    }

    @Test("nil experiencePlan emits no experience plan blocks")
    func nilExperiencePlanNoBlocks() {
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: nil
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasRecovery = blocks.contains { if case .failureRecoveryBlock = $0 { return true }; return false }
        let hasTransfer = blocks.contains { if case .transferPromptBlock = $0 { return true }; return false }
        let hasLoop = blocks.contains { if case .behaviorLoopBlock = $0 { return true }; return false }
        #expect(!hasRecovery)
        #expect(!hasTransfer)
        #expect(!hasLoop)
    }

    @Test("experience plan blocks appear after prompts (self-check, reflect)")
    func experiencePlanAfterPrompts() throws {
        let recovery = makeFullFailureRecovery()
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: makeExperiencePlan(failureRecovery: recovery)
        )
        let blocks = builder.build(from: makeChapter(
            selfCheckPrompts: ["Q?"],
            v21Extras: extras
        ))
        let selfCheckIdx = try #require(blocks.firstIndex {
            if case .heading("Self-Check", false) = $0 { return true }; return false
        })
        let recoveryIdx = try #require(blocks.firstIndex {
            if case .failureRecoveryBlock = $0 { return true }; return false
        })
        #expect(selfCheckIdx < recoveryIdx)
    }

    @Test("empty behaviorLoop (no patterns) emits no behaviorLoopBlock")
    func emptyBehaviorLoopNoBlock() {
        let loop = BehaviorLoop(readerPatterns: [])
        let extras = V21ChapterExtras(
            hook: nil,
            counterintuition: nil,
            tryThisNow: nil,
            keyTakeaway: nil,
            memorableLines: nil,
            experiencePlan: makeExperiencePlan(behaviorLoop: loop)
        )
        let blocks = builder.build(from: makeChapter(v21Extras: extras))
        let hasLoop = blocks.contains { if case .behaviorLoopBlock = $0 { return true }; return false }
        #expect(!hasLoop)
    }
}
