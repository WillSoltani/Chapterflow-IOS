import SwiftUI
import DesignSystem
import Models

/// Renders a real-world example with scenario, numbered steps, and rationale.
struct ExampleBlockView: View {
    let example: ResolvedExample

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            if let title = example.title, !title.isEmpty {
                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfAccent)
            }

            // Scenario
            sectionLabel("Scenario")
            Text(AttributedString.inlineMarkdown(example.scenario))
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .lineSpacing(3)

            if !example.whatToDo.isEmpty {
                Divider()
                    .padding(.vertical, .cfSpacing4)

                // What to do
                sectionLabel("What To Do")
                ForEach(Array(example.whatToDo.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: .cfSpacing12) {
                        Text("\(index + 1).")
                            .font(.cfCaption.monospacedDigit())
                            .foregroundStyle(Color.cfAccent)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(AttributedString.inlineMarkdown(step))
                            .font(.cfBody)
                            .foregroundStyle(Color.cfLabel)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()
                .padding(.vertical, .cfSpacing4)

            // Why it matters
            sectionLabel("Why It Matters")
            Text(AttributedString.inlineMarkdown(example.whyItMatters))
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineSpacing(3)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cfSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        .padding(.vertical, .cfSpacing8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.cfCaption2)
            .foregroundStyle(Color.cfTertiaryLabel)
            .kerning(0.6)
    }
}
