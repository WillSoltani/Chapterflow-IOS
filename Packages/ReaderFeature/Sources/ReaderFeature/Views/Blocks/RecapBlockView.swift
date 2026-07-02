import SwiftUI
import DesignSystem
import Models

/// Renders the one-minute recap — either a simple paragraph or the structured
/// retrieve / connect / preview form.
struct RecapBlockView: View {
    let recap: ResolvedOneMinuteRecap

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            if let text = recap.text {
                ReaderBodyText(text: AttributedString.inlineMarkdown(text))
            } else {
                if let retrieve = recap.retrieve {
                    recapSection(label: "Retrieve", text: retrieve)
                }
                if let connect = recap.connect {
                    recapSection(label: "Connect", text: connect)
                }
                if let preview = recap.preview {
                    recapSection(label: "Preview", text: preview)
                }
            }
        }
        .padding(.cfSpacing20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recapSection(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(label.uppercased())
                .font(.cfCaption2)
                .foregroundStyle(appearance.colors.accent)
                .kerning(0.6)
            Text(AttributedString.inlineMarkdown(text))
                .font(.cfCallout)
                .foregroundStyle(appearance.colors.primaryText)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
