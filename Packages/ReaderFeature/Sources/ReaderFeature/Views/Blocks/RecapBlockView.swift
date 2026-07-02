import SwiftUI
import DesignSystem
import Models

/// Renders the one-minute recap — either a simple paragraph or the structured
/// retrieve / connect / preview form.
struct RecapBlockView: View {
    let recap: ResolvedOneMinuteRecap

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            if let text = recap.text {
                Text(AttributedString.inlineMarkdown(text))
                    .font(.cfReaderBody())
                    .foregroundStyle(Color.cfLabel)
                    .lineSpacing(4)
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
        .background(Color.cfAccent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recapSection(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(label.uppercased())
                .font(.cfCaption2)
                .foregroundStyle(Color.cfAccent)
                .kerning(0.6)
            Text(AttributedString.inlineMarkdown(text))
                .font(.cfCallout)
                .foregroundStyle(Color.cfLabel)
                .lineSpacing(3)
        }
    }
}
