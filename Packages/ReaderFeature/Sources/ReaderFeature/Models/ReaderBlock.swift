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
    /// A highlighted callout box with a title and body (hook, tryThisNow,
    /// activation prompt, 24-hour challenge, etc.).
    case callout(title: String, body: String)
}
