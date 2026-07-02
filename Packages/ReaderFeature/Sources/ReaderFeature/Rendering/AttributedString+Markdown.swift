import Foundation

extension AttributedString {
    /// Parses inline Markdown emphasis (`*bold*`, `_italic_`, `**strong**`) from
    /// the given string.
    ///
    /// Uses `.inlineOnlyPreservingWhitespace` so only span-level markers are
    /// interpreted — paragraph breaks, headings, and other block-level syntax
    /// remain as plain text, preventing structural markdown from leaking through.
    ///
    /// Falls back to an unstyled `AttributedString` on parse failure so that
    /// raw asterisks or underscores are **never** visible to the reader.
    static func inlineMarkdown(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }
}
