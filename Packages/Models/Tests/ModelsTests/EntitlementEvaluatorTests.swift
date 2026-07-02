import Testing
import Foundation
@testable import Models

// MARK: - Test fixtures

private func makeEntitlement(
    plan: Entitlement.Plan = .free,
    proStatus: String? = nil,
    proSource: String? = nil,
    freeBookSlots: Int = 2,
    unlockedBookIds: [String] = [],
    unlockedBooksCount: Int = 0,
    remainingFreeStarts: Int = 0
) -> Entitlement {
    Entitlement(
        plan: plan,
        proStatus: proStatus,
        proSource: proSource,
        freeBookSlots: freeBookSlots,
        unlockedBookIds: unlockedBookIds,
        unlockedBooksCount: unlockedBooksCount,
        remainingFreeStarts: remainingFreeStarts,
        currentPeriodEnd: nil,
        cancelAtPeriodEnd: nil,
        licenseKey: nil,
        licenseExpiresAt: nil
    )
}

private func makeProgress(
    unlockedThrough: Int,
    completedChapters: [Int] = []
) -> BookProgress {
    BookProgress(
        currentChapterNumber: 1,
        unlockedThroughChapterNumber: unlockedThrough,
        completedChapters: completedChapters,
        bestScoreByChapter: [:],
        preferredVariant: nil,
        progressRev: nil
    )
}

private func makeState(
    unlockedChapterIds: [String] = [],
    completedChapterIds: [String] = []
) -> BookUserBookState {
    BookUserBookState(
        currentChapterId: nil,
        completedChapterIds: completedChapterIds,
        unlockedChapterIds: unlockedChapterIds,
        chapterScores: [:],
        chapterCompletedAt: [:],
        lastReadChapterId: nil,
        lastOpenedAt: nil
    )
}

// MARK: - isPro

@Suite("EntitlementEvaluator — isPro")
struct IsProTests {
    private let eval = EntitlementEvaluator()

    @Test("free plan is not pro")
    func freePlan() {
        #expect(!eval.isPro(makeEntitlement(plan: .free)))
    }

    @Test("pro plan with active status is pro")
    func proActive() {
        #expect(eval.isPro(makeEntitlement(plan: .pro, proStatus: "active")))
    }

    @Test("pro plan with canceled status is not pro")
    func proCanceled() {
        #expect(!eval.isPro(makeEntitlement(plan: .pro, proStatus: "canceled")))
    }

    @Test("pro plan with nil status is not pro")
    func proNilStatus() {
        #expect(!eval.isPro(makeEntitlement(plan: .pro, proStatus: nil)))
    }

    @Test("pro plan with past_due status is not pro")
    func proPastDue() {
        #expect(!eval.isPro(makeEntitlement(plan: .pro, proStatus: "past_due")))
    }

    @Test("pro plan with trialing status is not pro (must be active)")
    func proTrialing() {
        #expect(!eval.isPro(makeEntitlement(plan: .pro, proStatus: "trialing")))
    }
}

// MARK: - canStart

@Suite("EntitlementEvaluator — canStart")
struct CanStartTests {
    private let eval = EntitlementEvaluator()
    private let bookId = "b-atomic-habits"

    @Test("pro user can start any book")
    func proCanStartAny() {
        let entitlement = makeEntitlement(plan: .pro, proStatus: "active", remainingFreeStarts: 0)
        #expect(eval.canStart(bookId: bookId, entitlement: entitlement))
        #expect(eval.canStart(bookId: "b-unknown-book", entitlement: entitlement))
    }

    @Test("free user with book in unlockedBookIds can start it")
    func unlockedBook() {
        let entitlement = makeEntitlement(
            plan: .free,
            unlockedBookIds: [bookId],
            remainingFreeStarts: 0
        )
        #expect(eval.canStart(bookId: bookId, entitlement: entitlement))
    }

    @Test("free user with remaining free starts can start a new book")
    func hasRemainingFreeStarts() {
        let entitlement = makeEntitlement(plan: .free, remainingFreeStarts: 1)
        #expect(eval.canStart(bookId: bookId, entitlement: entitlement))
    }

    @Test("free user with no slots and book not unlocked cannot start")
    func noAccess() {
        let entitlement = makeEntitlement(plan: .free, unlockedBookIds: [], remainingFreeStarts: 0)
        #expect(!eval.canStart(bookId: bookId, entitlement: entitlement))
    }

    @Test("free user cannot start unlocked-by-id book if id doesn't match")
    func wrongBookId() {
        let entitlement = makeEntitlement(plan: .free, unlockedBookIds: ["b-other-book"], remainingFreeStarts: 0)
        #expect(!eval.canStart(bookId: bookId, entitlement: entitlement))
    }

    @Test("free user with both unlocked book and remaining slots can start")
    func multiplePaths() {
        let entitlement = makeEntitlement(plan: .free, unlockedBookIds: [bookId], remainingFreeStarts: 1)
        #expect(eval.canStart(bookId: bookId, entitlement: entitlement))
    }
}

// MARK: - isChapterUnlocked (by number)

@Suite("EntitlementEvaluator — isChapterUnlocked (by number)")
struct ChapterUnlockedByNumberTests {
    private let eval = EntitlementEvaluator()

    @Test("chapter within unlocked range is accessible")
    func withinRange() {
        let progress = makeProgress(unlockedThrough: 3)
        #expect(eval.isChapterUnlocked(number: 1, progress: progress))
        #expect(eval.isChapterUnlocked(number: 2, progress: progress))
        #expect(eval.isChapterUnlocked(number: 3, progress: progress))
    }

    @Test("chapter beyond unlocked range is not accessible")
    func beyondRange() {
        let progress = makeProgress(unlockedThrough: 3)
        #expect(!eval.isChapterUnlocked(number: 4, progress: progress))
        #expect(!eval.isChapterUnlocked(number: 10, progress: progress))
    }

    @Test("chapter 1 is always accessible when unlockedThrough >= 1")
    func firstChapter() {
        #expect(eval.isChapterUnlocked(number: 1, progress: makeProgress(unlockedThrough: 1)))
    }

    @Test("no chapters accessible when unlockedThrough is 0")
    func noneUnlocked() {
        let progress = makeProgress(unlockedThrough: 0)
        #expect(!eval.isChapterUnlocked(number: 1, progress: progress))
    }
}

// MARK: - isChapterUnlocked (by chapterId)

@Suite("EntitlementEvaluator — isChapterUnlocked (by chapterId)")
struct ChapterUnlockedByIdTests {
    private let eval = EntitlementEvaluator()

    @Test("chapter in unlockedChapterIds is accessible")
    func inList() {
        let state = makeState(unlockedChapterIds: ["ch-1", "ch-2"])
        #expect(eval.isChapterUnlocked(chapterId: "ch-1", state: state))
        #expect(eval.isChapterUnlocked(chapterId: "ch-2", state: state))
    }

    @Test("chapter not in unlockedChapterIds is not accessible")
    func notInList() {
        let state = makeState(unlockedChapterIds: ["ch-1"])
        #expect(!eval.isChapterUnlocked(chapterId: "ch-99", state: state))
    }

    @Test("empty unlockedChapterIds means nothing accessible")
    func emptyList() {
        let state = makeState(unlockedChapterIds: [])
        #expect(!eval.isChapterUnlocked(chapterId: "ch-1", state: state))
    }
}

// MARK: - Fixture-based integration

@Suite("EntitlementEvaluator — fixture integration")
struct EvaluatorFixtureTests {
    private let eval = EntitlementEvaluator()

    @Test("FREE fixture: not pro, has one remaining free start")
    func freeFixture() throws {
        let data = try fixtureData(named: "entitlement_free")
        let resp = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        let e = resp.entitlement
        #expect(!eval.isPro(e))
        // Book is in unlockedBookIds — always accessible
        #expect(eval.canStart(bookId: "b-atomic-habits", entitlement: e))
        // remainingFreeStarts = 1 — can start one more book
        #expect(eval.canStart(bookId: "b-brand-new", entitlement: e))
    }

    @Test("PRO fixture: is pro, can start any book")
    func proFixture() throws {
        let data = try fixtureData(named: "entitlement_pro")
        let resp = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        let e = resp.entitlement
        #expect(eval.isPro(e))
        #expect(eval.canStart(bookId: "b-any-book", entitlement: e))
        #expect(eval.canStart(bookId: "b-another-book", entitlement: e))
    }
}

private func fixtureData(named name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
        Issue.record("Missing fixture: Resources/\(name).json")
        struct Missing: Error {}
        throw Missing()
    }
    return try Data(contentsOf: url)
}
