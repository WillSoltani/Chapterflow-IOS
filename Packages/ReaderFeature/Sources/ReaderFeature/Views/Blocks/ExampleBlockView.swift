import SwiftUI
import DesignSystem
import Models

/// Renders a real-world example with scenario, numbered steps, and rationale.
struct ExampleBlockView: View {
    let example: ResolvedExample

    @Environment(\.readerAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            if let title = example.title, !title.isEmpty {
                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(appearance.colors.accent)
            }

            sectionLabel("Scenario")
            ReaderBodyText(text: AttributedString.inlineMarkdown(example.scenario))

            if !example.whatToDo.isEmpty {
                Divider()
                    .overlay(appearance.colors.separator)
                    .padding(.vertical, .cfSpacing4)

                sectionLabel("What To Do")
                ForEach(Array(example.whatToDo.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: .cfSpacing12) {
                        Text("\(index + 1).")
                            .font(.cfCaption.monospacedDigit())
                            .foregroundStyle(appearance.colors.accent)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(AttributedString.inlineMarkdown(step))
                            .font(.cfBody)
                            .foregroundStyle(appearance.colors.primaryText)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()
                .overlay(appearance.colors.separator)
                .padding(.vertical, .cfSpacing4)

            sectionLabel("Why It Matters")
            Text(AttributedString.inlineMarkdown(example.whyItMatters))
                .font(.cfCallout)
                .foregroundStyle(appearance.colors.secondaryText)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.cfCaption2)
            .foregroundStyle(appearance.colors.tertiaryText)
            .kerning(0.6)
    }
}
