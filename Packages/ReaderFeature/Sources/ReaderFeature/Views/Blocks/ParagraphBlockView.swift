import SwiftUI
import DesignSystem

/// Renders a narrative paragraph with the reader's serif body typography.
struct ParagraphBlockView: View {
    let text: String

    var body: some View {
        ReaderBodyText(text: AttributedString.inlineMarkdown(text))
            .padding(.vertical, .cfSpacing8)
    }
}
