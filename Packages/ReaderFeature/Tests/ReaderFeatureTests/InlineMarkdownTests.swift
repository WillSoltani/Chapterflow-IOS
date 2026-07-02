import Foundation
import Testing
@testable import ReaderFeature

@Suite("AttributedString.inlineMarkdown")
struct InlineMarkdownTests {
    @Test("plain text round-trips unchanged")
    func plainTextRoundTrips() {
        let input = "Hello, world."
        let result = AttributedString.inlineMarkdown(input)
        #expect(String(result.characters) == input)
    }

    @Test("bold markers are consumed and not visible in output")
    func boldMarkersConsumed() {
        let input = "This is **bold** text."
        let result = AttributedString.inlineMarkdown(input)
        let output = String(result.characters)
        #expect(!output.contains("*"))
        #expect(output.contains("bold"))
    }

    @Test("italic markers are consumed and not visible in output")
    func italicMarkersConsumed() {
        let input = "This is _italic_ text."
        let result = AttributedString.inlineMarkdown(input)
        let output = String(result.characters)
        #expect(!output.contains("_"))
        #expect(output.contains("italic"))
    }

    @Test("single asterisk bold markers are consumed")
    func singleAsteriskBoldConsumed() {
        let input = "This is *bold* text."
        let result = AttributedString.inlineMarkdown(input)
        let output = String(result.characters)
        #expect(!output.contains("*"))
        #expect(output.contains("bold"))
    }

    @Test("malformed markdown falls back to plain text without crashing")
    func malformedMarkdownFallsBack() {
        // Unclosed emphasis — should not crash and should not show raw markers
        let input = "Unclosed **bold"
        let result = AttributedString.inlineMarkdown(input)
        // Either the raw string or a recovered parse — must not crash
        #expect(!String(result.characters).isEmpty)
    }

    @Test("empty string returns empty AttributedString")
    func emptyStringReturnsEmpty() {
        let result = AttributedString.inlineMarkdown("")
        #expect(String(result.characters).isEmpty)
    }

    @Test("em-dash and smart quotes pass through unchanged")
    func specialCharactersPassThrough() {
        let input = "You don\u{2019}t rise \u{2014} you fall."
        let result = AttributedString.inlineMarkdown(input)
        #expect(String(result.characters) == input)
    }
}
