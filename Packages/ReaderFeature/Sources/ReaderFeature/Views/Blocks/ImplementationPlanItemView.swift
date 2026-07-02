import SwiftUI
import DesignSystem
import Models

/// Renders a single if-then implementation plan item.
struct ImplementationPlanItemView: View {
    let item: ResolvedIfThenPlan

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.cfBody)
                    .foregroundStyle(appearance.colors.accent)
                Text(AttributedString.inlineMarkdown(item.context))
                    .font(.cfCallout)
                    .foregroundStyle(appearance.colors.secondaryText)
                    .lineSpacing(2)
            }
            ReaderBodyText(text: AttributedString.inlineMarkdown(item.plan))
                .padding(.leading, .cfSpacing32)
        }
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("If \(item.context), then \(item.plan)")
    }
}
