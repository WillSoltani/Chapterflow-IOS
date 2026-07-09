import SwiftUI
import DesignSystem

/// Renders one Q&A exchange in the conversation thread.
///
/// The user's question appears right-aligned in an accent bubble.
/// The answer appears left-aligned in a neutral material card, with
/// tappable citation chips below it.
///
/// Long-pressing the answer card reveals a context menu with actions
/// to save the answer to the Notebook, copy it to the clipboard, and
/// share it with attribution (P6.7).
struct AskMessageView: View {
    let message: AskMessage
    let isPinned: Bool
    let onJumpToChapter: (Int) -> Void
    var onSaveToNotebook: ((AskMessage) -> Void)?
    var shareText: String?

    init(
        message: AskMessage,
        isPinned: Bool = false,
        onJumpToChapter: @escaping (Int) -> Void,
        onSaveToNotebook: ((AskMessage) -> Void)? = nil,
        shareText: String? = nil
    ) {
        self.message = message
        self.isPinned = isPinned
        self.onJumpToChapter = onJumpToChapter
        self.onSaveToNotebook = onSaveToNotebook
        self.shareText = shareText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            questionBubble
            answerCard
        }
        .padding(.horizontal, .cfSpacing16)
    }

    // MARK: - Question bubble

    private var questionBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: .cfSpacing4) {
                if let context = message.selectionContext {
                    selectionContextLabel(context)
                }
                Text(message.question)
                    .font(.cfBody)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing8)
                    .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your question: \(message.question)")
    }

    private func selectionContextLabel(_ context: String) -> some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10))
            Text(context.truncated(to: 60))
                .font(.cfCaption2)
                .lineLimit(1)
        }
        .foregroundStyle(Color.cfAccent.opacity(0.8))
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, 3)
        .background(Color.cfAccent.opacity(0.1), in: Capsule())
    }

    // MARK: - Answer card

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            HStack(alignment: .top) {
                AskAnswerText(text: message.answer)
                Spacer(minLength: 0)
                if isPinned {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.cfAccent)
                        .padding(.top, 2)
                        .accessibilityLabel("Saved to Notebook")
                }
            }

            if !message.citations.isEmpty {
                citationsRow
            }

            if message.isOnDeviceAnswer {
                onDeviceBadge
            }
        }
        .padding(.cfSpacing16)
        .background(answerBackground, in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous))
        .accessibilityElement(children: .contain)
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let save = onSaveToNotebook, !isPinned {
            Button {
                save(message)
            } label: {
                Label("Save to Notebook", systemImage: "bookmark")
            }
        }

        if let text = shareText {
            Button {
                #if os(iOS)
                UIPasteboard.general.string = text
                #endif
            } label: {
                Label("Copy Answer", systemImage: "doc.on.doc")
            }

            ShareLink(item: text) {
                Label("Share with Attribution", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var onDeviceBadge: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .medium))
            Text("Offline answer · Runs on your device")
                .font(.cfCaption2)
        }
        .foregroundStyle(Color.cfSecondaryLabel)
        .accessibilityLabel("This answer was generated on your device while offline")
    }

    private var citationsRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Sources")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)

            FlowLayout(spacing: .cfSpacing6) {
                ForEach(message.citations, id: \.self) { chapter in
                    CitationChipView(chapterNumber: chapter) {
                        onJumpToChapter(chapter)
                    }
                }
            }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var answerBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Flow layout for chips

/// A simple horizontal flow layout that wraps chips onto the next line.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += item.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem { let subview: LayoutSubview; let width: CGFloat }
    private struct Row { let items: [RowItem]; let height: CGFloat }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentItems: [RowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !currentItems.isEmpty {
                rows.append(Row(items: currentItems, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }
            currentItems.append(RowItem(subview: subview, width: size.width))
            currentWidth += size.width + spacing
            currentHeight = max(currentHeight, size.height)
        }
        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, height: currentHeight))
        }
        return rows
    }
}

// MARK: - Helpers

private extension String {
    func truncated(to length: Int) -> String {
        count <= length ? self : String(prefix(length)) + "…"
    }
}

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}
