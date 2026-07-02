import SwiftUI
import Models
import DesignSystem

/// The chapter block list — a lazy vertical stack of rendered `ReaderBlock` items.
///
/// Package-internal. Shared by `ReaderContentView` (which adds a `ScrollView`
/// wrapper) and `ReaderControlSurface` (which wraps it in a `ScrollViewReader`-
/// aware scroll container for anchor-based position restoration).
///
/// Each block is tagged `.id(index)` so callers can use `ScrollViewReader.scrollTo(_:anchor:)`
/// and `scrollPosition(id:)` to preserve the reader's position across content switches.
struct ReaderBlockListView: View {
    let blocks: [ReaderBlock]
    let appearance: ReadingAppearance
    /// When non-nil, every block is wrapped in `AnnotatedBlock` for highlight/note support.
    var annotationModel: AnnotationModel?
    /// Called when the user taps a cross-variant badge to switch depth/tone.
    var switchToVariantTone: ((String, String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                blockRow(index: index, block: blocks[index])
                    .padding(.horizontal, .cfSpacing24)
                    .id(index)
            }
        }
        .scrollTargetLayout()
        .padding(.vertical, .cfSpacing24)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Block row (with or without annotation wrapper)

    @ViewBuilder
    private func blockRow(index: Int, block: ReaderBlock) -> some View {
        if let annotationModel, !block.plainText.isEmpty {
            AnnotatedBlock(
                blockIndex: index,
                blockText: block.plainText,
                blockType: block.typeName,
                annotationModel: annotationModel,
                currentVariantLabel: annotationModel.currentVariantKey,
                currentToneLabel: annotationModel.currentToneKey,
                onSwitchVariantTone: switchToVariantTone
            ) {
                blockView(for: block)
            }
        } else {
            blockView(for: block)
        }
    }

    // MARK: - Block dispatch

    @ViewBuilder
    private func blockView(for block: ReaderBlock) -> some View {
        switch block {
        case .heading(let text, let isChapterTitle):
            HeadingBlockView(text: text, isChapterTitle: isChapterTitle)
        case .paragraph(let text):
            ParagraphBlockView(text: text)
        case .bullet(let text):
            BulletBlockView(text: text)
        case .keyTakeaway(let kt):
            KeyTakeawayBlockView(takeaway: kt)
        case .example(let ex):
            ExampleBlockView(example: ex)
        case .implementationPlanItem(let item):
            ImplementationPlanItemView(item: item)
        case .recap(let recap):
            RecapBlockView(recap: recap)
        case .pullQuote(let line):
            PullQuoteBlockView(line: line)
        case .callout(let title, let body):
            CalloutBlockView(title: title, bodyText: body)
        default:
            v21BlockView(for: block)
        }
    }

    /// Dispatches v21 premium-chrome and experience-plan blocks.
    ///
    /// Called via `default:` from `blockView(for:)` to keep that function's
    /// cyclomatic complexity within the project limit. New v21 cases must be
    /// added here exhaustively.
    @ViewBuilder
    private func v21BlockView(for block: ReaderBlock) -> some View {
        switch block {
        case .hookBanner(let text):
            HookBannerView(text: text)
        case .counterintuitionCallout(let text):
            CounterIntuitionView(text: text)
        case .tryThisNowDirective(let text):
            TryThisNowView(text: text)
        case .v21KeyTakeawayCard(let text):
            V21KeyTakeawayView(text: text)
        case .failureRecoveryBlock(let recovery):
            FailureRecoveryView(recovery: recovery)
        case .transferPromptBlock(let transfer):
            TransferPromptView(transfer: transfer)
        case .behaviorLoopBlock(let loop, let examples, let ifThenPlans):
            BehaviorLoopView(loop: loop, examples: examples, ifThenPlans: ifThenPlans)
        default:
            EmptyView()
        }
    }
}

// MARK: - ReaderBlock plain-text extraction

extension ReaderBlock {
    /// The plain text content of the block, used as the annotation anchor snippet.
    ///
    /// Returns `""` for purely structural blocks (behavior loops, etc.) where
    /// annotation doesn't make semantic sense; `AnnotatedBlock` skips those.
    var plainText: String {
        switch self {
        case .heading(let text, _):              return text
        case .paragraph(let text):              return text
        case .bullet(let text):                  return text
        case .hookBanner(let text):              return text
        case .counterintuitionCallout(let text): return text
        case .tryThisNowDirective(let text):     return text
        case .v21KeyTakeawayCard(let text):      return text
        case .pullQuote(let line):               return line.text
        case .callout(_, let body):              return body
        case .keyTakeaway(let kt):               return kt.point
        case .example(let ex):                   return ex.scenario
        case .implementationPlanItem(let item):  return item.plan
        case .recap(let recap):                  return recap.text ?? recap.retrieve ?? ""
        case .failureRecoveryBlock:              return ""
        case .transferPromptBlock:               return ""
        case .behaviorLoopBlock:                 return ""
        }
    }

    /// A short type identifier stored in the annotation anchor.
    var typeName: String {
        switch self {
        case .heading:                   return "heading"
        case .paragraph:                 return "paragraph"
        case .bullet:                    return "bullet"
        case .keyTakeaway:               return "keyTakeaway"
        case .example:                   return "example"
        case .implementationPlanItem:    return "implementationPlan"
        case .recap:                     return "recap"
        case .pullQuote:                 return "pullQuote"
        case .callout:                   return "callout"
        case .hookBanner:                return "hookBanner"
        case .counterintuitionCallout:   return "counterintuition"
        case .tryThisNowDirective:       return "tryThisNow"
        case .v21KeyTakeawayCard:        return "v21KeyTakeaway"
        case .failureRecoveryBlock:      return "failureRecovery"
        case .transferPromptBlock:       return "transferPrompt"
        case .behaviorLoopBlock:         return "behaviorLoop"
        }
    }
}
