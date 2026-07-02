import SwiftUI
import DesignSystem
import Models

/// Renders a memorable line as an elegant typographic pull-quote.
struct PullQuoteBlockView: View {
    let line: MemorableLine

    var body: some View {
        VStack(spacing: .cfSpacing12) {
            Text("\u{201C}")
                .font(.system(size: 52, weight: .thin, design: .serif))
                .foregroundStyle(Color.cfAccent)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

            Text(AttributedString.inlineMarkdown(line.text))
                .font(.system(.title3, design: .serif, weight: .light))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.cfLabel)
                .lineSpacing(5)
                .padding(.horizontal, .cfSpacing8)

            if let location = line.location, !location.isEmpty {
                Text("— \(location)")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .cfSpacing24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.text)
    }
}
