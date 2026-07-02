import SwiftUI
import DesignSystem
import Models

/// Renders a memorable line as an elegant typographic pull-quote.
struct PullQuoteBlockView: View {
    let line: MemorableLine

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(spacing: .cfSpacing12) {
            Text("\u{201C}")
                .font(.system(size: 52, weight: .thin, design: .serif))
                .foregroundStyle(appearance.colors.quoteBar)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

            ReaderQuoteText(text: AttributedString.inlineMarkdown(line.text))
                .padding(.horizontal, .cfSpacing8)

            if let location = line.location, !location.isEmpty {
                Text("— \(location)")
                    .font(.cfFootnote)
                    .foregroundStyle(appearance.colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .cfSpacing24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.text)
    }
}
