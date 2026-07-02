import SwiftUI
import DesignSystem
import Models

/// Renders a transfer prompt: the main prompt text and a set of context chips
/// encouraging the reader to apply the concept in diverse settings.
struct TransferPromptView: View {
    let transfer: TransferPrompt

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label {
                Text("APPLY IT ELSEWHERE")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
                    .kerning(0.8)
            } icon: {
                Image(systemName: "arrow.up.right.circle")
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.accent)
            }

            ReaderBodyText(text: AttributedString.inlineMarkdown(transfer.prompt))

            if !transfer.contexts.isEmpty {
                contextChips
            }
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var contextChips: some View {
        FlowLayout(spacing: .cfSpacing8) {
            ForEach(transfer.contexts, id: \.self) { context in
                Text(context)
                    .font(.cfCaption)
                    .foregroundStyle(appearance.colors.secondaryText)
                    .padding(.horizontal, .cfSpacing12)
                    .padding(.vertical, .cfSpacing4)
                    .background(appearance.colors.accent.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
    }

    private var accessibilityDescription: String {
        let contextList = transfer.contexts.joined(separator: ", ")
        return "Apply it elsewhere. \(transfer.prompt). Contexts: \(contextList)"
    }
}

/// A simple wrapping layout for chips/tags that flows to the next line when the
/// row is full. Replaces `LazyHGrid` for variable-width items.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
