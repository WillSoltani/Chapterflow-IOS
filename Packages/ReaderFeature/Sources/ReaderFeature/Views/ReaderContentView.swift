import SwiftUI
import Models
import DesignSystem

/// Renders a resolved chapter as a full-page reading flow.
///
/// Builds the block array once at init from the given `ResolvedChapter`, then
/// renders each `ReaderBlock` in order inside a lazy scroll view. No raw
/// `ToneKeyed` values or variant keys reach this layer — all content has
/// already been collapsed by `ChapterContentResolver`.
public struct ReaderContentView: View {
    private let blocks: [ReaderBlock]

    /// Initialise from a fully-resolved chapter.
    public init(chapter: ResolvedChapter) {
        self.blocks = ReaderContentBuilder().build(from: chapter)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(blocks.indices, id: \.self) { index in
                    blockView(for: blocks[index])
                        .padding(.horizontal, .cfSpacing24)
                }
            }
            .padding(.vertical, .cfSpacing24)
        }
        .background(Color.cfBackground)
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
        }
    }
}
