import Testing
@testable import ReaderFeature

@Suite("AnnotationAnchor")
struct AnnotationAnchorTests {

    // MARK: - JSON round-trip

    @Test("encodes and decodes to JSON faithfully")
    func jsonRoundTrip() throws {
        let anchor = AnnotationAnchor(
            variantKey: "medium",
            toneKey: "gentle",
            blockIndex: 5,
            blockType: "paragraph",
            startChar: 0,
            endChar: 42,
            snippet: "The quick brown fox jumped over the lazy dog."
        )
        let json = try #require(anchor.asJSON())
        let decoded = try #require(AnnotationAnchor.from(json: json))

        #expect(decoded == anchor)
        #expect(decoded.variantKey == "medium")
        #expect(decoded.toneKey == "gentle")
        #expect(decoded.blockIndex == 5)
        #expect(decoded.startChar == 0)
        #expect(decoded.endChar == 42)
        #expect(decoded.snippet == "The quick brown fox jumped over the lazy dog.")
    }

    @Test("from(json:) returns nil for garbage input")
    func fromJSONGarbage() {
        #expect(AnnotationAnchor.from(json: "not json") == nil)
        #expect(AnnotationAnchor.from(json: "") == nil)
        #expect(AnnotationAnchor.from(json: "{}") == nil)
    }

    // MARK: - validated(against:) — happy path

    @Test("validated returns self when range and snippet match")
    func validatedMatchingSnippet() {
        let text = "Hello world"
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 0, endChar: 5, snippet: "Hello"
        )
        let result = anchor.validated(against: text)
        #expect(result == anchor)
    }

    // MARK: - validated(against:) — degradation

    @Test("degrades to block-level when snippet does not match current text")
    func degradesOnSnippetMismatch() {
        let original = "The original sentence."
        let changed = "The content was updated by the server."
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 0, endChar: original.count, snippet: original
        )
        let result = anchor.validated(against: changed)
        #expect(result.startChar == 0)
        #expect(result.endChar == changed.count)
        #expect(result.snippet == original) // snippet preserved (it's the original selection)
        #expect(result.variantKey == anchor.variantKey)
        #expect(result.blockIndex == anchor.blockIndex)
    }

    @Test("degrades when startChar is out of bounds")
    func degradesOnOutOfBoundsStart() {
        let text = "Short"
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 1, blockType: "paragraph",
            startChar: 100, endChar: 200, snippet: "anything"
        )
        let result = anchor.validated(against: text)
        #expect(result.startChar == 0)
        #expect(result.endChar == text.count)
    }

    @Test("degrades when endChar exceeds text length")
    func degradesOnOutOfBoundsEnd() {
        let text = "Hello"
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 0, endChar: 999, snippet: "Hello"
        )
        let result = anchor.validated(against: text)
        #expect(result.startChar == 0)
        #expect(result.endChar == text.count)
    }

    @Test("degrades when startChar equals endChar")
    func degradesOnEmptyRange() {
        let text = "Hello"
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 2, endChar: 2, snippet: ""
        )
        let result = anchor.validated(against: text)
        #expect(result.startChar == 0)
        #expect(result.endChar == text.count)
    }

    // MARK: - isBlockLevel

    @Test("isBlockLevel is true when range spans the whole snippet")
    func isBlockLevelTrue() {
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 0, endChar: 5, snippet: "Hello"
        )
        #expect(anchor.isBlockLevel == true)
    }

    @Test("isBlockLevel is false for a sub-range")
    func isBlockLevelFalse() {
        let anchor = AnnotationAnchor(
            variantKey: "medium", toneKey: "gentle",
            blockIndex: 0, blockType: "paragraph",
            startChar: 0, endChar: 3, snippet: "Hello"
        )
        #expect(anchor.isBlockLevel == false)
    }
}
