import Testing
import Foundation
@testable import CoreKit

@Suite("DeepLink — custom scheme")
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

    @Test("parses the paywall link")
    func paywall() {
        #expect(link("chapterflow://paywall") == .paywall)
    }

    @Test("parses a journey link")
    func journey() {
        #expect(link("chapterflow://journey/j-summer-reads") == .journey(id: "j-summer-reads"))
    }

    @Test("journey link without id resolves to .unknown")
    func journeyMissingId() {
        let url = URL(string: "chapterflow://journey")!
        #expect(link("chapterflow://journey") == .unknown(url))
    }

    @Test("parses an event link")
    func event() {
        #expect(link("chapterflow://event/ev-2024-nov") == .event(id: "ev-2024-nov"))
    }

    @Test("event link without id resolves to .unknown")
    func eventMissingId() {
        let url = URL(string: "chapterflow://event")!
        #expect(link("chapterflow://event") == .unknown(url))
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
        #expect(link("https://example.com/book/1") == nil)
    }

    @Test("parses the library link")
    func library() {
        #expect(link("chapterflow://library") == .library)
    }

    @Test("parses the profile link")
    func profile() {
        #expect(link("chapterflow://profile") == .profile)
    }

    @Test("parses profile with sub-path as .profile")
    func profileSubPath() {
        #expect(link("chapterflow://profile/badges") == .profile)
    }

    @Test("parses the engagement link")
    func engagement() {
        #expect(link("chapterflow://engagement") == .engagement)
    }

    @Test("parses the notifications link")
    func notifications() {
        #expect(link("chapterflow://notifications") == .notifications)
    }
}

// MARK: - Universal Links (https://chapterflow.app/...)

@Suite("DeepLink — Universal Links")
struct DeepLinkUniversalLinkTests {
    private func link(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    @Test("Universal Link: book")
    func bookUniversalLink() {
        #expect(link("https://chapterflow.app/book/abc123") == .book(id: "abc123"))
    }

    @Test("Universal Link: chapter")
    func chapterUniversalLink() {
        #expect(link("https://chapterflow.app/book/abc123/chapter/4") == .chapter(bookId: "abc123", chapter: 4))
    }

    @Test("Universal Link: pair accept")
    func pairAcceptUniversalLink() {
        #expect(link("https://chapterflow.app/pair/accept/XYZ") == .pairAccept(code: "XYZ"))
    }

    @Test("Universal Link: gift")
    func giftUniversalLink() {
        #expect(link("https://chapterflow.app/gift/GIFTCODE") == .gift(code: "GIFTCODE"))
    }

    @Test("Universal Link: referral")
    func referralUniversalLink() {
        #expect(link("https://chapterflow.app/ref/ALICE42") == .referral(code: "ALICE42"))
    }

    @Test("Universal Link: review")
    func reviewUniversalLink() {
        #expect(link("https://chapterflow.app/review") == .review)
    }

    @Test("Universal Link: paywall")
    func paywallUniversalLink() {
        #expect(link("https://chapterflow.app/paywall") == .paywall)
    }

    @Test("Universal Link: journey")
    func journeyUniversalLink() {
        #expect(link("https://chapterflow.app/journey/j-summer-reads") == .journey(id: "j-summer-reads"))
    }

    @Test("Universal Link: event")
    func eventUniversalLink() {
        #expect(link("https://chapterflow.app/event/ev-2024-nov") == .event(id: "ev-2024-nov"))
    }

    @Test("Universal Link: library")
    func libraryUniversalLink() {
        #expect(link("https://chapterflow.app/library") == .library)
    }

    @Test("Universal Link: profile")
    func profileUniversalLink() {
        #expect(link("https://chapterflow.app/profile") == .profile)
    }

    @Test("Universal Link: profile sub-path treated as .profile")
    func profileSubPathUniversalLink() {
        #expect(link("https://chapterflow.app/profile/badges") == .profile)
    }

    @Test("Universal Link: engagement")
    func engagementUniversalLink() {
        #expect(link("https://chapterflow.app/engagement") == .engagement)
    }

    @Test("Universal Link: notifications")
    func notificationsUniversalLink() {
        #expect(link("https://chapterflow.app/notifications") == .notifications)
    }

    @Test("wrong domain is rejected")
    func wrongDomainRejected() {
        #expect(link("https://evil.com/book/1") == nil)
    }

    @Test("http (not https) is rejected")
    func httpRejected() {
        #expect(link("http://chapterflow.app/book/1") == nil)
    }

    @Test("Universal Link: unknown path resolves to .unknown")
    func unknownPathUniversalLink() {
        let url = URL(string: "https://chapterflow.app/some/unknown/path")!
        #expect(link("https://chapterflow.app/some/unknown/path") == .unknown(url))
    }

    @Test("Universal Link: non-numeric chapter degrades to book")
    func nonNumericChapterUniversalLink() {
        #expect(link("https://chapterflow.app/book/abc/chapter/nan") == .book(id: "abc"))
    }

    @Test("scheme constant is 'chapterflow'")
    func schemeConstant() {
        #expect(DeepLink.scheme == "chapterflow")
    }

    @Test("universalLinkDomain constant is 'chapterflow.app'")
    func domainConstant() {
        #expect(DeepLink.universalLinkDomain == "chapterflow.app")
    }
}
