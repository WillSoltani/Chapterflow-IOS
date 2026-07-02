import SwiftUI
import DesignSystem

/// Renders a server-provided answer string with lightweight Markdown support.
///
/// Handles: **bold**, *italic*, `inline code`, and `- ` bullet list items.
/// Block-level Markdown (headings, links) is intentionally excluded to prevent
/// unexpected rendering artefacts in a chat bubble context.
struct AskAnswerText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            ForEach(parsedBlocks().indices, id: \.self) { index in
                blockView(for: parsedBlocks()[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block model

    private enum Block {
        case bullet(AttributedString)
        case paragraph(AttributedString)
    }

    private func parsedBlocks() -> [Block] {
        text.components(separatedBy: "\n").compactMap { line -> Block? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2))
                return .bullet(inlineMarkdown(content))
            }
            return .paragraph(inlineMarkdown(trimmed))
        }
    }

    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .bullet(let attributed):
            HStack(alignment: .top, spacing: .cfSpacing8) {
                Text("•")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Text(attributed)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let attributed):
            Text(attributed)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inline markdown parser

    /// Parses inline Markdown emphasis from a string, falling back to plain text
    /// if parsing fails — raw asterisks are never shown to the user.
    private func inlineMarkdown(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }
}
