import SwiftUI
import DesignSystem

/// A small pill badge shown on a block when it has highlights in a DIFFERENT
/// (variant, tone) pair than the one currently being read.
///
/// Tapping the badge fires `onTap`, which the host wires to
/// `ReaderControlsModel.switchVariant(_:currentTopIndex:)` and
/// `switchTone(_:currentTopIndex:)` to let the user jump to the annotated view.
struct BlockAnnotationBadge: View {
    let count: Int
    let variantLabel: String
    let toneLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "highlighter")
                    .imageScale(.small)
                Text(label)
                    .font(.cfCaption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.cfAccent)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(Color.cfAccent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) highlight\(count == 1 ? "" : "s") in \(variantLabel), \(toneLabel). Tap to switch.")
    }

    private var label: String {
        let n = count == 1 ? "1 highlight" : "\(count) highlights"
        return "\(n) in \(variantLabel) · \(toneLabel)"
    }
}

#if DEBUG
#Preview("Badge — single") {
    BlockAnnotationBadge(
        count: 1,
        variantLabel: "Medium",
        toneLabel: "Gentle",
        onTap: {}
    )
    .padding()
}

#Preview("Badge — multiple") {
    BlockAnnotationBadge(
        count: 3,
        variantLabel: "Easy",
        toneLabel: "Direct",
        onTap: {}
    )
    .padding()
}
#endif
