import Testing
@testable import DesignSystem

@Suite("PseudoLocalization")
struct PseudoLocalizationTests {

    @Test("accents Latin letters")
    func accentsLetters() {
        let out = PseudoLocalization.transform("Read", style: .accented)
        // No ASCII a–z / A–Z should survive inside the pseudo body.
        let inner = out.drop(while: { $0 != "⟦" }).dropFirst().prefix(while: { $0 != "⟧" })
        #expect(!inner.contains(where: { $0.isASCII && $0.isLetter }))
    }

    @Test("wraps in brackets to reveal truncation boundaries")
    func wrapsInBrackets() {
        let out = PseudoLocalization.transform("Hi", style: .accented)
        #expect(out.hasPrefix("⟦"))
        #expect(out.hasSuffix("⟧"))
    }

    @Test("expands length so truncation shows in previews")
    func expandsLength() {
        let source = "Continue Reading"
        let out = PseudoLocalization.transform(source, style: .accented)
        #expect(out.count > source.count)
        // Bidi expands more than accented.
        let bidi = PseudoLocalization.transform(source, style: .bidi)
        #expect(bidi.count > out.count)
    }

    @Test("preserves printf-style format specifiers verbatim")
    func preservesFormatSpecifiers() {
        for spec in ["%@", "%lld", "%1$@", "%2$lld", "%%"] {
            let out = PseudoLocalization.transform("Value: \(spec)", style: .accented)
            #expect(out.contains(spec), "specifier \(spec) must survive, got: \(out)")
        }
    }

    @Test("does not corrupt a multi-argument format string")
    func multiArgumentFormat() {
        let out = PseudoLocalization.accentPreservingFormatSpecifiers("%1$@ by %2$@")
        #expect(out.contains("%1$@"))
        #expect(out.contains("%2$@"))
        // The word "by" is accented (no ASCII letters remain).
        #expect(!out.contains(" by "))
    }

    @Test("bidi style adds RTL isolates")
    func bidiAddsIsolates() {
        let out = PseudoLocalization.transform("Menu", style: .bidi)
        #expect(out.hasPrefix("\u{2067}"))   // RIGHT-TO-LEFT ISOLATE
        #expect(out.hasSuffix("\u{2069}"))   // POP DIRECTIONAL ISOLATE
    }

    @Test("leaves whitespace and punctuation legible")
    func keepsPunctuation() {
        let out = PseudoLocalization.transform("A, B.", style: .accented)
        #expect(out.contains(","))
        #expect(out.contains("."))
    }
}
