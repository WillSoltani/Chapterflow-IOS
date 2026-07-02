import SwiftUI
import DesignSystem
import Models

/// Renders a key-takeaway card with an accent stripe, headline, and
/// optional elaboration text.
struct KeyTakeawayBlockView: View {
    let takeaway: ResolvedKeyTakeaway

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        HStack(spacing: 0) {
            // Accent stripe
            Rectangle()
                .fill(appearance.colors.quoteBar)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text(AttributedString.inlineMarkdown(takeaway.point))
                    .font(.cfHeadline)
                    .foregroundStyle(appearance.colors.primaryText)
                    .lineSpacing(2)
                if let details = takeaway.moreDetails, !details.isEmpty {
                    Text(AttributedString.inlineMarkdown(details))
                        .font(.cfBody)
                        .foregroundStyle(appearance.colors.secondaryText)
                        .lineSpacing(3)
                }
            }
            .padding(.cfSpacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }
}
