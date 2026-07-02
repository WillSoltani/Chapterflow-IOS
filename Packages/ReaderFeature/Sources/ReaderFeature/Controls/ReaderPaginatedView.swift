#if os(iOS)
import SwiftUI
import Models
import DesignSystem

/// A page-based reading view where each page contains one chapter section.
///
/// Sections are delimited by `ReaderBlock.heading` entries. Swipe left or
/// right to advance through pages — same content as the scroll view, arranged
/// for a focused, page-at-a-time reading experience.
///
/// The page indicator at the bottom shows progress. When blocks are rebuilt
/// (depth or tone change), the caller should reset `currentPage` to 0.
public struct ReaderPaginatedView: View {
    private let pages: [[ReaderBlock]]
    @Binding private var currentPage: Int
    private let appearance: ReadingAppearance

    public init(
        blocks: [ReaderBlock],
        currentPage: Binding<Int>,
        appearance: ReadingAppearance
    ) {
        self.pages = Self.buildPages(from: blocks)
        self._currentPage = currentPage
        self.appearance = appearance
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    ScrollView {
                        ReaderBlockListView(blocks: pages[index], appearance: appearance)
                    }
                    .background(appearance.colors.pageBg)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(appearance.colors.pageBg)

            if pages.count > 1 {
                pageIndicator
            }
        }
        .readerAppearance(appearance)
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: .cfSpacing4) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.cfAccent : Color.cfSeparator)
                    .frame(
                        width: index == currentPage ? 7 : 5,
                        height: index == currentPage ? 7 : 5
                    )
                    .animation(.spring(duration: 0.2), value: currentPage)
            }
        }
        .padding(.vertical, .cfSpacing8)
        .padding(.horizontal, .cfSpacing16)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, .cfSpacing32)
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
        .accessibilityValue("\(currentPage + 1)")
    }

    // MARK: - Page segmentation

    /// Groups blocks into pages: each heading starts a new page.
    private static func buildPages(from blocks: [ReaderBlock]) -> [[ReaderBlock]] {
        guard !blocks.isEmpty else { return [[]] }

        var pages: [[ReaderBlock]] = []
        var current: [ReaderBlock] = []

        for block in blocks {
            if case .heading = block, !current.isEmpty {
                pages.append(current)
                current = []
            }
            current.append(block)
        }

        if !current.isEmpty {
            pages.append(current)
        }

        return pages.isEmpty ? [[]] : pages
    }
}
#endif
