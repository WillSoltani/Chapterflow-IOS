import SwiftUI
import DesignSystem
import Models

/// Renders a key-takeaway card with an accent stripe, headline, and
/// optional elaboration text.
struct KeyTakeawayBlockView: View {
    let takeaway: ResolvedKeyTakeaway

    var body: some View {
        HStack(spacing: 0) {
            // Accent stripe
            Rectangle()
                .fill(Color.cfAccent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text(AttributedString.inlineMarkdown(takeaway.point))
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                    .lineSpacing(2)
                if let details = takeaway.moreDetails, !details.isEmpty {
                    Text(AttributedString.inlineMarkdown(details))
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineSpacing(3)
                }
            }
            .padding(.cfSpacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.cfSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }
}
