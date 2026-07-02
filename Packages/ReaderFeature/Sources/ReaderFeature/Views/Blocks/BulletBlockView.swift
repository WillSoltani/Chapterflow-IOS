import SwiftUI
import DesignSystem

/// Renders a single bullet-point list item.
struct BulletBlockView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Circle()
                .fill(Color.cfAccent)
                .frame(width: 5, height: 5)
                .padding(.top, 8)
            Text(AttributedString.inlineMarkdown(text))
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, .cfSpacing4)
    }
}
