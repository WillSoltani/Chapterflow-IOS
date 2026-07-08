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

// MARK: - Universal Links (https://app.chapterflow.ca/...)

@Suite("DeepLink — Universal Links (app.chapterflow.ca)")
struct DeepLinkAppDomainTests {
    private func link(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    @Test("UL app-domain: book")
    func bookUniversalLink() {
        #expect(link("https://app.chapterflow.ca/book/abc123") == .book(id: "abc123"))
    }

    @Test("UL app-domain: chapter")
    func chapterUniversalLink() {
        #expect(link("https://app.chapterflow.ca/book/abc123/chapter/4") == .chapter(bookId: "abc123", chapter: 4))
    }

    @Test("UL app-domain: pair accept")
    func pairAcceptUniversalLink() {
        #expect(link("https://app.chapterflow.ca/pair/accept/XYZ") == .pairAccept(code: "XYZ"))
    }

    @Test("UL app-domain: gift")
    func giftUniversalLink() {
        #expect(link("https://app.chapterflow.ca/gift/GIFTCODE") == .gift(code: "GIFTCODE"))
    }

    @Test("UL app-domain: referral")
    func referralUniversalLink() {
        #expect(link("https://app.chapterflow.ca/ref/ALICE42") == .referral(code: "ALICE42"))
    }

    @Test("UL app-domain: review")
    func reviewUniversalLink() {
        #expect(link("https://app.chapterflow.ca/review") == .review)
    }

    @Test("UL app-domain: paywall")
    func paywallUniversalLink() {
        #expect(link("https://app.chapterflow.ca/paywall") == .paywall)
    }

    @Test("UL app-domain: journey")
    func journeyUniversalLink() {
        #expect(link("https://app.chapterflow.ca/journey/j-summer-reads") == .journey(id: "j-summer-reads"))
    }

    @Test("UL app-domain: event")
    func eventUniversalLink() {
        #expect(link("https://app.chapterflow.ca/event/ev-2024-nov") == .event(id: "ev-2024-nov"))
    }

    @Test("UL app-domain: library")
    func libraryUniversalLink() {
        #expect(link("https://app.chapterflow.ca/library") == .library)
    }

    @Test("UL app-domain: profile")
    func profileUniversalLink() {
        #expect(link("https://app.chapterflow.ca/profile") == .profile)
    }

    @Test("UL app-domain: profile sub-path treated as .profile")
    func profileSubPathUniversalLink() {
        #expect(link("https://app.chapterflow.ca/profile/badges") == .profile)
    }

    @Test("UL app-domain: engagement")
    func engagementUniversalLink() {
        #expect(link("https://app.chapterflow.ca/engagement") == .engagement)
    }

    @Test("UL app-domain: notifications")
    func notificationsUniversalLink() {
        #expect(link("https://app.chapterflow.ca/notifications") == .notifications)
    }

    @Test("UL app-domain: unknown path resolves to .unknown")
    func unknownPathUniversalLink() {
        let url = URL(string: "https://app.chapterflow.ca/some/unknown/path")!
        #expect(link("https://app.chapterflow.ca/some/unknown/path") == .unknown(url))
    }

    @Test("UL app-domain: non-numeric chapter degrades to book")
    func nonNumericChapterUniversalLink() {
        #expect(link("https://app.chapterflow.ca/book/abc/chapter/nan") == .book(id: "abc"))
    }
}

// MARK: - Universal Links (https://chapterflow.ca/...)

@Suite("DeepLink — Universal Links (chapterflow.ca root domain)")
struct DeepLinkRootDomainTests {
    private func link(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    @Test("UL root-domain: book parses identically to app-domain")
    func bookRootDomain() {
        #expect(link("https://chapterflow.ca/book/abc123") == .book(id: "abc123"))
    }

    @Test("UL root-domain: chapter parses identically to app-domain")
    func chapterRootDomain() {
        #expect(link("https://chapterflow.ca/book/abc123/chapter/4") == .chapter(bookId: "abc123", chapter: 4))
    }

    @Test("UL root-domain: pair accept")
    func pairAcceptRootDomain() {
        #expect(link("https://chapterflow.ca/pair/accept/XYZ") == .pairAccept(code: "XYZ"))
    }

    @Test("UL root-domain: review")
    func reviewRootDomain() {
        #expect(link("https://chapterflow.ca/review") == .review)
    }

    @Test("UL root-domain: paywall")
    func paywallRootDomain() {
        #expect(link("https://chapterflow.ca/paywall") == .paywall)
    }
}

// MARK: - Rejection cases

@Suite("DeepLink — rejection cases")
struct DeepLinkRejectionTests {
    private func link(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    @Test("wrong domain is rejected")
    func wrongDomainRejected() {
        #expect(link("https://evil.com/book/1") == nil)
    }

    @Test("http (not https) is rejected for UL domains")
    func httpRejected() {
        #expect(link("http://app.chapterflow.ca/book/1") == nil)
    }

    @Test("chapterflow.app is not our domain and is rejected")
    func wrongAppDomainRejected() {
        #expect(link("https://chapterflow.app/book/1") == nil)
    }

    @Test("scheme constant is 'chapterflow'")
    func schemeConstant() {
        #expect(DeepLink.scheme == "chapterflow")
    }

    @Test("universalLinkDomains contains both live domains")
    func domainsConstant() {
        #expect(DeepLink.universalLinkDomains.contains("chapterflow.ca"))
        #expect(DeepLink.universalLinkDomains.contains("app.chapterflow.ca"))
    }

    @Test("webAppDomain is app.chapterflow.ca")
    func webAppDomainConstant() {
        #expect(DeepLink.webAppDomain == "app.chapterflow.ca")
    }
}
