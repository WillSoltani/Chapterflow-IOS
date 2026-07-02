import Foundation
import Models

/// Maps a `ResolvedChapter` into an ordered `[ReaderBlock]` array ready for rendering.
///
/// The canonical reading order follows the P2.4 master spec:
/// title → hook → counterintuition → breakdown → key takeaways →
/// examples → tryThisNow → memorable lines → v21 key takeaway →
/// implementation plan → recap → activation → self-check → reflection
///
/// Every optional section is silently omitted when absent — no empty blocks
/// are ever emitted.
public struct ReaderContentBuilder: Sendable {
    public init() {}

    /// Builds the ordered block array for `chapter`.
    public func build(from chapter: ResolvedChapter) -> [ReaderBlock] {
        var blocks: [ReaderBlock] = [.heading(chapter.title, isChapterTitle: true)]

        appendV21Opening(chapter.v21Extras, to: &blocks)
        appendNarrative(chapter, to: &blocks)
        appendKeyTakeaways(chapter, to: &blocks)
        appendExamples(chapter, to: &blocks)
        appendV21Premium(chapter.v21Extras, to: &blocks)

        if let plan = chapter.implementationPlan {
            appendImplementationPlan(plan, to: &blocks)
        }

        appendPractice(chapter, to: &blocks)
        appendRecap(chapter, to: &blocks)
        appendPrompts(chapter, to: &blocks)

        return blocks
    }

    // MARK: - Section helpers

    private func appendV21Opening(
        _ extras: V21ChapterExtras?,
        to blocks: inout [ReaderBlock]
    ) {
        if let hook = extras?.hook, !hook.isEmpty {
            blocks.append(.callout(title: "Hook", body: hook))
        }
        if let ci = extras?.counterintuition, !ci.isEmpty {
            blocks.append(.callout(title: "Counterintuition", body: ci))
        }
    }

    private func appendNarrative(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        if let breakdown = chapter.chapterBreakdown, !breakdown.isEmpty {
            blocks.append(.paragraph(breakdown))
        }
        if let summary = chapter.importantSummary, !summary.isEmpty {
            blocks.append(.paragraph(summary))
        }
        for bullet in chapter.summaryBullets where !bullet.isEmpty {
            blocks.append(.bullet(bullet))
        }
    }

    private func appendKeyTakeaways(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        if !chapter.keyTakeaways.isEmpty {
            blocks.append(.heading("Key Takeaways"))
            chapter.keyTakeaways.forEach { blocks.append(.keyTakeaway($0)) }
        }
        for item in chapter.takeaways where !item.isEmpty {
            blocks.append(.bullet(item))
        }
    }

    private func appendExamples(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        guard !chapter.examples.isEmpty else { return }
        blocks.append(.heading("Examples"))
        chapter.examples.forEach { blocks.append(.example($0)) }
    }

    private func appendV21Premium(
        _ extras: V21ChapterExtras?,
        to blocks: inout [ReaderBlock]
    ) {
        if let ttn = extras?.tryThisNow, !ttn.isEmpty {
            blocks.append(.callout(title: "Try This Now", body: ttn))
        }
        if let lines = extras?.memorableLines {
            lines.filter { !$0.text.isEmpty }.forEach { blocks.append(.pullQuote($0)) }
        }
        if let kt = extras?.keyTakeaway, !kt.isEmpty {
            blocks.append(.callout(title: "Key Takeaway", body: kt))
        }
    }

    private func appendPractice(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        guard !chapter.practice.isEmpty else { return }
        blocks.append(.heading("Practice"))
        for item in chapter.practice where !item.isEmpty {
            blocks.append(.bullet(item))
        }
    }

    private func appendRecap(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        guard let recap = chapter.oneMinuteRecap else { return }
        blocks.append(.heading("One-Minute Recap"))
        blocks.append(.recap(recap))
    }

    private func appendPrompts(_ chapter: ResolvedChapter, to blocks: inout [ReaderBlock]) {
        if let activation = chapter.activationPrompt, !activation.isEmpty {
            blocks.append(.callout(title: "Activation", body: activation))
        }
        if !chapter.selfCheckPrompts.isEmpty {
            blocks.append(.heading("Self-Check"))
            chapter.selfCheckPrompts.filter { !$0.isEmpty }.forEach { blocks.append(.bullet($0)) }
        }
        if !chapter.reflectionPrompts.isEmpty {
            blocks.append(.heading("Reflect"))
            chapter.reflectionPrompts.filter { !$0.isEmpty }.forEach { blocks.append(.bullet($0)) }
        }
    }

    private func appendImplementationPlan(
        _ plan: ResolvedImplementationPlan,
        to blocks: inout [ReaderBlock]
    ) {
        let hasContent = plan.coreSkill != nil
            || plan.concreteAction != nil
            || !plan.ifThenPlans.isEmpty
            || plan.twentyFourHourChallenge != nil
            || plan.weeklyPractice != nil
            || plan.friction != nil
            || plan.checkpoint != nil
        guard hasContent else { return }

        blocks.append(.heading("Implementation Plan"))

        if let skill = plan.coreSkill, !skill.isEmpty { blocks.append(.paragraph(skill)) }
        if let action = plan.concreteAction, !action.isEmpty { blocks.append(.paragraph(action)) }
        plan.ifThenPlans.forEach { blocks.append(.implementationPlanItem($0)) }
        if let c = plan.twentyFourHourChallenge, !c.isEmpty {
            blocks.append(.callout(title: "24-Hour Challenge", body: c))
        }
        if let w = plan.weeklyPractice, !w.isEmpty { blocks.append(.bullet(w)) }
        if let f = plan.friction, !f.isEmpty { blocks.append(.callout(title: "Common Friction", body: f)) }
        if let ch = plan.checkpoint, !ch.isEmpty { blocks.append(.callout(title: "Checkpoint", body: ch)) }
    }
}
