import Testing
import Foundation
@testable import CoreKit

@Suite("DeepLink")
struct DeepLinkTests {
    private func link(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    @Test("parses a book link")
    func book() {
        #expect(link("chapterflow://book/abc123") == .book(id: "abc123"))
    }

    @Test("parses a chapter link")
    func chapter() {
        #expect(link("chapterflow://book/abc123/chapter/4") == .chapter(bookId: "abc123", chapter: 4))
    }

    @Test("parses a pairing acceptance link")
    func pairAccept() {
        #expect(link("chapterflow://pair/accept/XYZ") == .pairAccept(code: "XYZ"))
    }

    @Test("parses a gift link")
    func gift() {
        #expect(link("chapterflow://gift/GIFT99") == .gift(code: "GIFT99"))
    }

    @Test("parses a referral invite link")
    func referral() {
        #expect(link("chapterflow://ref/ALICE42") == .referral(code: "ALICE42"))
    }

    @Test("referral link with missing code resolves to .unknown")
    func referralMissingCode() {
        let url = URL(string: "chapterflow://ref")!
        #expect(link("chapterflow://ref") == .unknown(url))
    }

    @Test("parses the review link")
    func review() {
        #expect(link("chapterflow://review") == .review)
    }

    @Test("recognized scheme but unknown path resolves to .unknown")
    func unknownPath() {
        let url = URL(string: "chapterflow://something/weird")!
        #expect(link("chapterflow://something/weird") == .unknown(url))
    }

    @Test("a non-numeric chapter degrades to the book link")
    func nonNumericChapter() {
        #expect(link("chapterflow://book/abc/chapter/notanumber") == .book(id: "abc"))
    }

    @Test("foreign schemes are rejected")
    func foreignScheme() {
        #expect(link("https://chapterflow.app/book/1") == nil)
    }
}
