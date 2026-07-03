import SwiftUI
import Models
import DesignSystem

/// A single concept node in the graph canvas.
struct ConceptNodeView: View {

    let node: ConceptNode
    let isSelected: Bool
    let isHighlighted: Bool
    let isDimmed: Bool
    let onTap: () -> Void

    private var fillColor: Color {
        if isSelected { return .cfAccent }
        if isHighlighted { return .cfAccent.opacity(0.15) }
        return .cfSecondaryBackground
    }

    private var strokeColor: Color {
        if isSelected { return .cfAccent }
        if isHighlighted { return .cfAccent }
        return .cfSeparator
    }

    private var strokeWidth: CGFloat {
        isSelected || isHighlighted ? 2 : 1
    }

    private var labelColor: Color {
        if isSelected { return .white }
        if isDimmed { return .cfTertiaryLabel }
        return .cfLabel
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay(
                        Circle()
                            .strokeBorder(strokeColor, lineWidth: strokeWidth)
                    )
                    .frame(width: .nodeRadius * 2, height: .nodeRadius * 2)
                    .opacity(isDimmed ? 0.4 : 1.0)

                Text(node.label)
                    .font(.cfCaption2)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: .nodeRadius * 2 - .cfSpacing8)
            }
        }
        .buttonStyle(.plain)
        .frame(width: .nodeRadius * 2, height: .nodeRadius * 2)
        .accessibilityLabel(node.label)
        .accessibilityHint(node.summary.map { String($0.prefix(80)) } ?? "No summary available")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
