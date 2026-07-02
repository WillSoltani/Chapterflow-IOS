import SwiftUI
import DesignSystem

/// Renders a narrative paragraph with the reader's serif body typography.
struct ParagraphBlockView: View {
    let text: String

    var body: some View {
        Text(AttributedString.inlineMarkdown(text))
            .font(.cfReaderBody())
            .foregroundStyle(Color.cfLabel)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, .cfSpacing8)
    }
}
