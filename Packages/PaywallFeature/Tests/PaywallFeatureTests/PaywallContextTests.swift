import Testing
@testable import PaywallFeature

@Suite("PaywallContext")
struct PaywallContextTests {

    // MARK: - Headline

    @Test("bookDetail headline includes book title")
    func bookDetailHeadline() {
        let ctx = PaywallContext.bookDetail(bookTitle: "Atomic Habits")
        #expect(ctx.headline == "Unlock \"Atomic Habits\"")
    }

    @Test("lockedFeature headline includes feature name")
    func lockedFeatureHeadline() {
        let ctx = PaywallContext.lockedFeature(featureName: "AI Deep Dive")
        #expect(ctx.headline == "Unlock AI Deep Dive")
    }

    @Test("settings headline is ChapterFlow Pro")
    func settingsHeadline() {
        #expect(PaywallContext.settings.headline == "ChapterFlow Pro")
    }

    // MARK: - Subtitle

    @Test("bookDetail subtitle mentions unlimited books")
    func bookDetailSubtitle() {
        let ctx = PaywallContext.bookDetail(bookTitle: "X")
        #expect(!ctx.subtitle.isEmpty)
    }

    @Test("lockedFeature subtitle mentions Pro members")
    func lockedFeatureSubtitle() {
        let ctx = PaywallContext.lockedFeature(featureName: "X")
        #expect(ctx.subtitle.lowercased().contains("pro"))
    }

    @Test("settings subtitle is non-empty")
    func settingsSubtitle() {
        #expect(!PaywallContext.settings.subtitle.isEmpty)
    }

    // MARK: - Analytics source

    @Test("bookDetail analyticsSource is book_detail")
    func bookDetailAnalyticsSource() {
        #expect(PaywallContext.bookDetail(bookTitle: "X").analyticsSource == "book_detail")
    }

    @Test("lockedFeature analyticsSource is locked_feature")
    func lockedFeatureAnalyticsSource() {
        #expect(PaywallContext.lockedFeature(featureName: "X").analyticsSource == "locked_feature")
    }

    @Test("settings analyticsSource is settings")
    func settingsAnalyticsSource() {
        #expect(PaywallContext.settings.analyticsSource == "settings")
    }

    // MARK: - Equatable

    @Test("same bookDetail contexts are equal")
    func bookDetailEquality() {
        #expect(
            PaywallContext.bookDetail(bookTitle: "A") ==
            PaywallContext.bookDetail(bookTitle: "A")
        )
    }

    @Test("different bookDetail contexts are not equal")
    func bookDetailInequality() {
        #expect(
            PaywallContext.bookDetail(bookTitle: "A") !=
            PaywallContext.bookDetail(bookTitle: "B")
        )
    }

    @Test("settings equals settings")
    func settingsEquality() {
        #expect(PaywallContext.settings == PaywallContext.settings)
    }
}
