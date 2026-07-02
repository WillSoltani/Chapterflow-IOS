import Foundation
import Models

/// A single renderable unit in the reader's content flow.
///
/// `ReaderContentBuilder` maps a `ResolvedChapter` into an ordered `[ReaderBlock]`.
/// Views render from this array; no raw `ToneKeyed` values or variant keys
/// ever reach this layer.
public enum ReaderBlock: Sendable {
    // MARK: - Structure

    /// A heading — either the chapter title (isChapterTitle == true) or a
    /// named section label such as "Key Takeaways" or "Examples".
    case heading(String, isChapterTitle: Bool = false)

    // MARK: - Prose

    /// A narrative paragraph (chapterBreakdown, coreSkill, concreteAction, etc.).
    case paragraph(String)
    /// A single bullet-point item (summaryBullets, reflections, self-check, etc.).
    case bullet(String)

    // MARK: - Teaching content

    /// A key-takeaway card with a headline and optional elaboration.
    case keyTakeaway(ResolvedKeyTakeaway)
    /// A real-world example with scenario, ordered steps, and rationale.
    case example(ResolvedExample)
    /// A single if-then implementation plan item.
    case implementationPlanItem(ResolvedIfThenPlan)
    /// The chapter's one-minute recap — simple string or structured
    /// retrieve / connect / preview form.
    case recap(ResolvedOneMinuteRecap)

    // MARK: - Visual emphasis

    /// An elegant pull-quote from the chapter's memorable lines.
    case pullQuote(MemorableLine)
    /// A highlighted callout box with a title and body (24-hour challenge,
    /// activation prompt, common friction, checkpoint, etc.).
    case callout(title: String, body: String)

    // MARK: - v21 Premium Chrome

    /// The chapter's attention-grabbing hook banner rendered above the narrative.
    case hookBanner(String)
    /// A counterintuition callout — the "twist" that reframes the reader's assumption.
    case counterintuitionCallout(String)
    /// A directive "Try This Now" action block.
    case tryThisNowDirective(String)
    /// The v21 chapter-level key takeaway card (a single string summary).
    case v21KeyTakeawayCard(String)

    // MARK: - v21 Experience Plan

    /// Failure-recovery guidance: normalising line, cue question, options, and repair.
    case failureRecoveryBlock(FailureRecovery)
    /// A transfer prompt encouraging the reader to apply the concept in new contexts.
    case transferPromptBlock(TransferPrompt)
    /// An interactive behavior-loop selector: reader archetypes that map to examples/plans.
    case behaviorLoopBlock(BehaviorLoop, examples: [ResolvedExample], ifThenPlans: [ResolvedIfThenPlan])
}
