import SwiftUI
import Models
import DesignSystem
import Persistence

/// Renders a resolved chapter as a full-page reading flow.
///
/// Builds the block array once at init from the given `ResolvedChapter`, then
/// renders each `ReaderBlock` in order inside a lazy scroll view. No raw
/// `ToneKeyed` values or variant keys reach this layer — all content has
/// already been collapsed by `ChapterContentResolver`.
///
/// Supply `AppPreferences` to have theme, font scale, and line spacing applied
/// reactively. The appearance tokens flow down through the SwiftUI environment
/// so every block view updates instantly when preferences change.
public struct ReaderContentView: View {
    private let blocks: [ReaderBlock]
    private let preferences: AppPreferences?

    /// Initialise from a fully-resolved chapter with user preferences.
    public init(chapter: ResolvedChapter, preferences: AppPreferences? = nil) {
        self.blocks = ReaderContentBuilder().build(from: chapter)
        self.preferences = preferences
    }

    public var body: some View {
        // Computed here (inside `body`, which is @MainActor) so that accessing
        // AppPreferences's @MainActor-isolated properties is valid.
        let appearance = preferences.map { ReadingAppearance(preferences: $0) } ?? .default
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(blocks.indices, id: \.self) { index in
                    blockView(for: blocks[index])
                        .padding(.horizontal, .cfSpacing24)
                }
            }
            .padding(.vertical, .cfSpacing24)
            // Constrain line measure to ~66ch for optimal readability on wide screens.
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(appearance.colors.pageBg)
        .readerAppearance(appearance)
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
