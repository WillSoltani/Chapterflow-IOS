import Testing
import Foundation
@testable import Models

// MARK: - Fixture loading helper

private func fixture(named name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
        Issue.record("Missing fixture file: Resources/\(name).json")
        struct MissingFixture: Error {}
        throw MissingFixture()
    }
    return try Data(contentsOf: url)
}

// MARK: - Catalog

@Suite("Catalog decoding")
struct CatalogDecodingTests {
    @Test("decodes catalog response without loss")
    func decodeCatalog() throws {
        let data = try fixture(named: "catalog")
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books.count == 3)

        let atomic = try #require(response.books.first { $0.bookId == "b-atomic-habits" })
        #expect(atomic.title == "Atomic Habits")
        #expect(atomic.author == "James Clear")
        #expect(atomic.variantFamily == .emh)
        #expect(atomic.cover?.emoji == "⚛️")
        #expect(atomic.cover?.color == "#2D6A4F")
        #expect(atomic.categories.contains("Productivity"))

        let deepWork = try #require(response.books.first { $0.bookId == "b-deep-work" })
        #expect(deepWork.variantFamily == .pbc)
    }

    @Test("BookCatalogItem is Identifiable via bookId")
    func catalogIdentifiable() throws {
        let data = try fixture(named: "catalog")
        let response = try JSONDecoder.chapterFlow.decode(CatalogResponse.self, from: data)
        #expect(response.books[0].id == response.books[0].bookId)
    }
}

// MARK: - EMH Chapter

@Suite("EMH chapter decoding")
struct EMHChapterDecodingTests {
    private func chapter() throws -> Chapter {
        let data = try fixture(named: "chapter_emh")
        let resp = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        return resp.chapter
    }

    @Test("decodes chapter metadata")
    func metadata() throws {
        let ch = try chapter()
        #expect(ch.chapterId == "ch-ah-1")
        #expect(ch.number == 1)
        #expect(ch.title == "The Surprising Power of Atomic Habits")
        #expect(ch.activeVariant == .medium)
        #expect(ch.availableVariants == [.easy, .medium, .hard])
    }

    @Test("decodes all three content variants")
    func allVariants() throws {
        let ch = try chapter()
        #expect(ch.contentVariants.count == 3)
        #expect(ch.typedContentVariants[.easy] != nil)
        #expect(ch.typedContentVariants[.medium] != nil)
        #expect(ch.typedContentVariants[.hard] != nil)
    }

    @Test("decodes examples with mixed String and ToneKeyed union types")
    func examplesUnionTypes() throws {
        let ch = try chapter()
        #expect(ch.examples.count == 2)

        // First example: whatToDo is [String], scenario and whyItMatters are mixed
        let ex0 = ch.examples[0]
        if case .strings(let steps) = ex0.whatToDo {
            #expect(steps.count == 3)
        } else {
            Issue.record("Expected .strings for example[0].whatToDo")
        }
        if case .string = ex0.scenario {
            // OK
        } else {
            Issue.record("Expected .string for example[0].scenario")
        }
        if case .toneKeyed = ex0.whyItMatters {
            // OK
        } else {
            Issue.record("Expected .toneKeyed for example[0].whyItMatters")
        }

        // Second example: scenario and whatToDo are ToneKeyed, whyItMatters is plain string
        let ex1 = ch.examples[1]
        if case .toneKeyed = ex1.scenario {
            // OK
        } else {
            Issue.record("Expected .toneKeyed for example[1].scenario")
        }
        if case .toneKeyed = ex1.whatToDo {
            // OK
        } else {
            Issue.record("Expected .toneKeyed for example[1].whatToDo")
        }
        if case .string = ex1.whyItMatters {
            // OK
        } else {
            Issue.record("Expected .string for example[1].whyItMatters")
        }
    }

    @Test("decodes v21Extras including experiencePlan")
    func v21Extras() throws {
        let ch = try chapter()
        let extras = try #require(ch.v21Extras)
        #expect(extras.hook != nil)
        #expect(extras.counterintuition != nil)
        #expect(extras.memorableLines?.count == 2)
        #expect(extras.experiencePlan?.failureRecovery != nil)
        #expect(extras.experiencePlan?.transferPrompt != nil)
        #expect(extras.experiencePlan?.behaviorLoop?.readerPatterns.count == 3)
    }

    @Test("decodes implementationPlan with ifThenPlans")
    func implementationPlan() throws {
        let ch = try chapter()
        let plan = try #require(ch.implementationPlan)
        #expect(plan.coreSkill != nil)
        #expect(plan.ifThenPlans?.count == 1)
        #expect(plan.twentyFourHourChallenge != nil)
        #expect(plan.weeklyPractice != nil)
    }

    @Test("decodes reviewCards")
    func reviewCards() throws {
        let ch = try chapter()
        let cards = try #require(ch.reviewCards)
        #expect(cards.count == 2)
        #expect(cards[0].cardId == "rc-ah-1-1")
        #expect(cards[0].front.gentle != "")
        #expect(cards[0].back.direct != "")
    }

    @Test("decodes keyTakeawayCard")
    func keyTakeawayCard() throws {
        let ch = try chapter()
        let card = try #require(ch.keyTakeawayCard)
        #expect(!card.gentle.isEmpty)
        #expect(!card.direct.isEmpty)
        #expect(!card.competitive.isEmpty)
    }

    @Test("decodes progress alongside chapter")
    func progress() throws {
        let data = try fixture(named: "chapter_emh")
        let resp = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        #expect(resp.progress.currentChapterNumber == 1)
        #expect(resp.progress.unlockedThroughChapterNumber == 1)
    }

    @Test("decodes simple oneMinuteRecap form (ToneKeyed)")
    func simpleOneMinuteRecap() throws {
        let ch = try chapter()
        let medContent = try #require(ch.typedContentVariants[.medium])
        let recap = try #require(medContent.oneMinuteRecap)
        if case .simple(let tk) = recap {
            #expect(!tk.gentle.isEmpty)
        } else {
            Issue.record("Expected .simple oneMinuteRecap for medium variant")
        }
    }

    @Test("decodes structured oneMinuteRecap form (retrieve/connect/preview)")
    func structuredOneMinuteRecap() throws {
        let ch = try chapter()
        let hardContent = try #require(ch.typedContentVariants[.hard])
        let recap = try #require(hardContent.oneMinuteRecap)
        if case .structured(let r, let c, let p) = recap {
            #expect(!r.gentle.isEmpty)
            #expect(!c.direct.isEmpty)
            #expect(!p.competitive.isEmpty)
        } else {
            Issue.record("Expected .structured oneMinuteRecap for hard variant")
        }
    }
}

// MARK: - PBC Chapter

@Suite("PBC chapter decoding")
struct PBCChapterDecodingTests {
    private func chapter() throws -> Chapter {
        let data = try fixture(named: "chapter_pbc")
        let resp = try JSONDecoder.chapterFlow.decode(ChapterResponse.self, from: data)
        return resp.chapter
    }

    @Test("decodes PBC variant family keys")
    func pbcVariants() throws {
        let ch = try chapter()
        #expect(ch.activeVariant == .balanced)
        #expect(ch.availableVariants == [.precise, .balanced, .challenging])
        #expect(ch.typedContentVariants[.precise] != nil)
        #expect(ch.typedContentVariants[.balanced] != nil)
        #expect(ch.typedContentVariants[.challenging] != nil)
    }

    @Test("v21Extras is nil for PBC chapter")
    func noV21Extras() throws {
        let ch = try chapter()
        #expect(ch.v21Extras == nil)
    }

    @Test("challenging variant has structured oneMinuteRecap")
    func challengingStructuredRecap() throws {
        let ch = try chapter()
        let content = try #require(ch.typedContentVariants[.challenging])
        let recap = try #require(content.oneMinuteRecap)
        if case .structured = recap {
            // OK
        } else {
            Issue.record("Expected .structured oneMinuteRecap for challenging variant")
        }
    }
}

// MARK: - Quiz

@Suite("Quiz decoding")
struct QuizDecodingTests {
    @Test("decodes quiz client session")
    func decodeQuiz() throws {
        let data = try fixture(named: "quiz")
        let resp = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: data)
        #expect(resp.quiz.questions.count == 3)
        #expect(resp.quiz.passingScorePercent == 70)
        #expect(resp.quiz.bookId == "b-atomic-habits")
    }

    @Test("decodes questions with both prompt and stem fields")
    func promptAndStem() throws {
        let data = try fixture(named: "quiz")
        let resp = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: data)
        // q-ah-1-1 uses "prompt", q-ah-1-2 uses "stem" — both should decode
        let q1 = try #require(resp.quiz.questions.first { $0.questionId == "q-ah-1-1" })
        #expect(!q1.prompt.isEmpty)
        let q2 = try #require(resp.quiz.questions.first { $0.questionId == "q-ah-1-2" })
        #expect(!q2.prompt.isEmpty) // unified into `prompt` from `stem`
    }

    @Test("decodes quiz choices with choiceId scheme")
    func quizChoices() throws {
        let data = try fixture(named: "quiz")
        let resp = try JSONDecoder.chapterFlow.decode(QuizResponse.self, from: data)
        let q = resp.quiz.questions[0]
        #expect(q.choices.count == 4)
        #expect(q.choices.allSatisfy { !$0.choiceId.isEmpty })
    }

    @Test("decodes quiz attempt result")
    func quizResult() throws {
        let data = try fixture(named: "quiz_result")
        let result = try JSONDecoder.chapterFlow.decode(QuizAttemptResult.self, from: data)
        #expect(result.passed == true)
        #expect(result.scorePercent == 100)
        #expect(result.correctCount == 3)
        #expect(result.unlockedNextChapter == true)
        #expect(result.questionResults.count == 3)
        #expect(result.questionResults.allSatisfy { $0.isCorrect })
    }
}

// MARK: - Entitlement

@Suite("Entitlement decoding")
struct EntitlementDecodingTests {
    @Test("decodes FREE entitlement with paywall")
    func freeEntitlement() throws {
        let data = try fixture(named: "entitlement_free")
        let resp = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(resp.entitlement.plan == .free)
        #expect(resp.entitlement.proStatus == nil)
        #expect(resp.entitlement.remainingFreeStarts == 1)
        #expect(resp.entitlement.unlockedBookIds == ["b-atomic-habits"])
        let paywall = try #require(resp.paywall)
        #expect(paywall.pricingTiers.count == 2)
        #expect(paywall.benefits.count == 5)
    }

    @Test("decodes PRO entitlement")
    func proEntitlement() throws {
        let data = try fixture(named: "entitlement_pro")
        let resp = try JSONDecoder.chapterFlow.decode(EntitlementResponse.self, from: data)
        #expect(resp.entitlement.plan == .pro)
        #expect(resp.entitlement.proStatus == "active")
        #expect(resp.entitlement.proSource == "apple")
        #expect(resp.entitlement.cancelAtPeriodEnd == false)
    }
}

// MARK: - Book state

@Suite("Book state decoding")
struct BookStateDecodingTests {
    @Test("decodes book user state with applicationStates")
    func bookState() throws {
        let data = try fixture(named: "book_state")
        let resp = try JSONDecoder.chapterFlow.decode(BookStateGetResponse.self, from: data)
        #expect(resp.stateStatus == nil)
        #expect(resp.state.completedChapterIds == ["ch-ah-1"])
        #expect(resp.state.unlockedChapterIds.count == 2)
        #expect(resp.state.chapterScores["ch-ah-1"] == 100)
        #expect(resp.applicationStates?["ch-ah-1"] == .applied)
        #expect(resp.applicationStates?["ch-ah-2"] == .committed)
    }
}
