import SwiftUI
import DesignSystem
import Models

/// Renders a single if-then implementation plan item.
struct ImplementationPlanItemView: View {
    let item: ResolvedIfThenPlan

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfAccent)
                Text(AttributedString.inlineMarkdown(item.context))
                    .font(.cfCallout)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .lineSpacing(2)
            }
            Text(AttributedString.inlineMarkdown(item.plan))
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .lineSpacing(3)
                .padding(.leading, .cfSpacing32)
        }
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("If \(item.context), then \(item.plan)")
    }
}
