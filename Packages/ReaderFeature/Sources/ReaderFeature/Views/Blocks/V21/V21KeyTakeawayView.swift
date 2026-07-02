import SwiftUI
import DesignSystem

/// The v21 chapter-level key takeaway card — a single-sentence summary insight.
///
/// Distinct from `KeyTakeawayBlockView` (which renders a `ResolvedKeyTakeaway`
/// struct with optional details). This is the chapter's final word: a compact,
/// typographic statement styled as a centered italic serif quote with a lightbulb
/// marker.
struct V21KeyTakeawayView: View {
    let text: String

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(appearance.colors.quoteBar)

            Text(AttributedString.inlineMarkdown(text))
                .font(.system(size: takeawayFontSize, weight: .light, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(appearance.colors.primaryText)
                .lineSpacing(appearance.lineSpacing + 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.cfSpacing24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: .cfRadius16)
                .fill(appearance.colors.surfaceBg)
            RoundedRectangle(cornerRadius: .cfRadius16)
                .strokeBorder(appearance.colors.quoteBar.opacity(0.35), lineWidth: 1)
        }
        .padding(.vertical, .cfSpacing12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key takeaway. \(text)")
    }

    @ScaledMetric(relativeTo: .title3) private var takeawayFontSize: CGFloat = 19
}
