import SwiftUI
import DesignSystem

/// Renders a single bullet-point list item.
struct BulletBlockView: View {
    let text: String

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Circle()
                .fill(appearance.colors.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 8)
            ReaderBodyText(text: AttributedString.inlineMarkdown(text))
        }
        .padding(.vertical, .cfSpacing4)
    }
}
