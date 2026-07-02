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

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(for: blocks[index])
                    .padding(.horizontal, .cfSpacing24)
                    .id(index)
            }
        }
        .scrollTargetLayout()
        .padding(.vertical, .cfSpacing24)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
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
