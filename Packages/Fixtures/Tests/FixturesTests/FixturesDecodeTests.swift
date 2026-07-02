import Testing
import Models
@testable import Fixtures

/// Verifies that every fixture JSON file decodes into its model type without any
/// data loss or decoding errors. These tests act as a contract between the JSON
/// files and the Codable models — if a model field is renamed or a JSON key
/// changes, these tests catch it immediately.
@Suite("Fixtures decode")
struct FixturesDecodeTests {

    // MARK: - Catalog

    @Test("catalog: decodes 3 books")
    func catalogDecodes() {
        let catalog = Fixtures.catalog
        #expect(catalog.books.count == 3)
        #expect(catalog.books[0].bookId == "b-atomic-habits")
        #expect(catalog.books[0].variantFamily == .emh)
        #expect(catalog.books[1].bookId == "b-deep-work")
        #expect(catalog.books[1].variantFamily == .pbc)
        #expect(catalog.books[2].bookId == "b-thinking-fast-slow")
    }

    @Test("book manifest: decodes 5 chapters")
    func bookManifestDecodes() {
        let manifest = Fixtures.bookManifest
        #expect(manifest.bookId == "b-atomic-habits")
        #expect(manifest.chapters.count == 5)
        #expect(manifest.chapters[0].number == 1)
        #expect(manifest.chapterCount == 5)
        #expect(manifest.totalReadingTimeMinutes == 120)
    }

    // MARK: - Chapters

    @Test("chapter EMH: decodes with v21Extras populated")
    func chapterEMHDecodes() {
        let response = Fixtures.chapterEMH
        let chapter = response.chapter
        #expect(chapter.chapterId == "ch-ah-1")
        #expect(chapter.activeVariant == .medium)
        #expect(chapter.availableVariants.count == 3)
        #expect(chapter.contentVariants.count == 3)
        #expect(chapter.v21Extras != nil)
        #expect(chapter.v21Extras?.hook != nil)
        #expect(chapter.v21Extras?.memorableLines?.isEmpty == false)
        #expect(chapter.v21Extras?.experiencePlan?.failureRecovery != nil)
        #expect(chapter.reviewCards?.isEmpty == false)
        #expect(chapter.implementationPlan != nil)
        #expect(response.progress.progressRev == 1)
    }

    @Test("chapter PBC: decodes with v21Extras nil")
    func chapterPBCDecodes() {
        let response = Fixtures.chapterPBC
        let chapter = response.chapter
        #expect(chapter.chapterId == "ch-dw-1")
        #expect(chapter.activeVariant == .balanced)
        #expect(chapter.availableVariants.count == 3)
        #expect(chapter.v21Extras == nil)
        #expect(chapter.reviewCards?.isEmpty == false)
    }

    @Test("resolved EMH chapter: key fields present")
    func resolvedEMHDecodes() {
        let resolved = Fixtures.resolvedEMH
        #expect(resolved.chapterId == "ch-ah-1")
        #expect(resolved.resolvedVariant == .medium)
        #expect(resolved.resolvedTone == .direct)
        #expect(resolved.chapterBreakdown != nil)
        #expect(resolved.keyTakeaways.isEmpty == false)
        #expect(resolved.activationPrompt != nil)
        #expect(resolved.reviewCards.isEmpty == false)
    }

    @Test("resolved PBC chapter: key fields present")
    func resolvedPBCDecodes() {
        let resolved = Fixtures.resolvedPBC
        #expect(resolved.chapterId == "ch-dw-1")
        #expect(resolved.resolvedVariant == .balanced)
        #expect(resolved.resolvedTone == .gentle)
        #expect(resolved.chapterBreakdown != nil)
        #expect(resolved.v21Extras == nil)
    }

    @Test("concept graph: decodes nodes, edges and chapter maps")
    func conceptGraphDecodes() {
        let graph = Fixtures.conceptGraph
        #expect(graph.concepts.count == 6)
        #expect(graph.edges.isEmpty == false)
        #expect(graph.chapterIntroduces?.isEmpty == false)
        #expect(graph.chapterRequires?.isEmpty == false)
    }

    // MARK: - Quiz

    @Test("quiz session: decodes 3 questions with mixed prompt/stem keys")
    func quizSessionDecodes() {
        let response = Fixtures.quizSession
        let quiz = response.quiz
        #expect(quiz.sessionId == "qs-ah-1-abc123")
        #expect(quiz.questions.count == 3)
        // All questions must have a resolved prompt (even those using the legacy `stem` key)
        for q in quiz.questions {
            #expect(q.prompt.isEmpty == false)
            #expect(q.choices.count == 4)
        }
        #expect(quiz.passingScorePercent == 70)
    }

    @Test("quiz result passed: all correct")
    func quizResultPassedDecodes() {
        let result = Fixtures.quizResultPassed
        #expect(result.passed == true)
        #expect(result.scorePercent == 100)
        #expect(result.correctCount == 3)
        #expect(result.unlockedNextChapter == true)
        #expect(result.cooldownSeconds == 0)
        #expect(result.questionResults.count == 3)
        for qr in result.questionResults {
            #expect(qr.isCorrect == true)
        }
    }

    @Test("quiz result failed: cooldown active")
    func quizResultFailedDecodes() {
        let result = Fixtures.quizResultFailed
        #expect(result.passed == false)
        #expect(result.scorePercent == 33)
        #expect(result.correctCount == 1)
        #expect(result.unlockedNextChapter == false)
        #expect(result.cooldownSeconds == 300)
        #expect(result.nextEligibleAttemptAt != nil)
    }

    // MARK: - Entitlement

    @Test("entitlement FREE: plan, slots, paywall")
    func entitlementFreeDecodes() {
        let response = Fixtures.entitlementFree
        let ent = response.entitlement
        #expect(ent.plan == .free)
        #expect(ent.proStatus == nil)
        #expect(ent.unlockedBookIds.contains("b-atomic-habits"))
        #expect(ent.remainingFreeStarts == 1)
        let pw = response.paywall
        #expect(pw != nil)
        #expect(pw?.pricingTiers.count == 2)
        #expect(pw?.benefits.isEmpty == false)
    }

    @Test("entitlement PRO: active Apple subscription")
    func entitlementProDecodes() {
        let response = Fixtures.entitlementPro
        let ent = response.entitlement
        #expect(ent.plan == .pro)
        #expect(ent.proStatus == "active")
        #expect(ent.proSource == "apple")
        #expect(ent.currentPeriodEnd != nil)
        #expect(response.paywall == nil)
    }

    // MARK: - Book state

    @Test("book state: completed and unlocked chapters")
    func bookStateDecodes() {
        let state = Fixtures.bookState
        #expect(state.state.completedChapterIds.contains("ch-ah-1"))
        #expect(state.state.unlockedChapterIds.contains("ch-ah-2"))
        #expect(state.applicationStates?["ch-ah-1"] == .applied)
        #expect(state.applicationStates?["ch-ah-2"] == .committed)
    }

    // MARK: - Dashboard

    @Test("dashboard: streak, tier, continue book")
    func dashboardDecodes() {
        let response = Fixtures.dashboard
        let dash = response.dashboard
        #expect(dash.currentStreak == 5)
        #expect(dash.longestStreak == 12)
        #expect(dash.tier == "analyst")
        #expect(dash.dueReviewCount == 4)
        #expect(dash.continueBook?.bookId == "b-atomic-habits")
        #expect(dash.weeklyReadMinutes <= dash.weeklyGoalMinutes)
    }

    // MARK: - Streak

    @Test("streak: current/longest, shields, history")
    func streakDecodes() {
        let response = Fixtures.streak
        let streak = response.streak
        #expect(streak.currentStreak == 5)
        #expect(streak.longestStreak == 12)
        #expect(streak.streakShieldsHeld == 1)
        #expect(streak.lastActivityDate != nil)
        #expect(streak.streakHistory?.count == 5)
    }

    // MARK: - Badges

    @Test("badges: earned and locked")
    func badgesDecodes() {
        let response = Fixtures.badges
        #expect(response.badges.count == 4)
        let earned = response.badges.filter(\.isEarned)
        let locked = response.badges.filter { !$0.isEarned }
        #expect(earned.count == 2)
        #expect(locked.count == 2)
        for badge in earned {
            #expect(badge.earnedAt != nil)
        }
    }

    // MARK: - Notebook

    @Test("notebook: mixed entry types")
    func notebookDecodes() {
        let response = Fixtures.notebook
        let entries = response.entries
        #expect(entries.count == 5)
        let types = Set(entries.map(\.type))
        #expect(types.contains(.note))
        #expect(types.contains(.highlight))
        #expect(types.contains(.commitment))
        #expect(types.contains(.reflection))
        #expect(types.contains(.bookmark))
        // highlights have a quote, notes have content
        let highlight = entries.first { $0.type == .highlight }
        #expect(highlight?.quote != nil)
        let note = entries.first { $0.type == .note }
        #expect(note?.content != nil)
    }

    // MARK: - Reviews

    @Test("reviews: due count and card states")
    func reviewsDecodes() {
        let response = Fixtures.reviews
        #expect(response.dueCount == 2)
        #expect(response.cards.count == 3)
        let dueCards = response.cards.filter { $0.state == .due }
        #expect(dueCards.count == 2)
        let newCards = response.cards.filter { $0.state == .new }
        #expect(newCards.count == 1)
    }

    // MARK: - Notifications

    @Test("notifications: unread count and deep links")
    func notificationsDecodes() {
        let response = Fixtures.notificationsResponse
        #expect(response.notifications.count == 4)
        #expect(response.unreadCount == 2)
        let unread = response.notifications.filter { !$0.isRead }
        #expect(unread.count == 2)
        for notif in response.notifications {
            #expect(notif.title.isEmpty == false)
            #expect(notif.body.isEmpty == false)
        }
    }

    // MARK: - PreviewDependencies

    @Test("PreviewDependencies.shared: all fields populated")
    func previewDependenciesShared() {
        let deps = PreviewDependencies.shared
        #expect(deps.books.count == 3)
        #expect(deps.bookManifest.chapters.count == 5)
        #expect(deps.chapterEMH.chapter.v21Extras != nil)
        #expect(deps.chapterPBC.chapter.v21Extras == nil)
        #expect(deps.quizSession.quiz.questions.count == 3)
        #expect(deps.quizResultPassed.passed == true)
        #expect(deps.quizResultFailed.passed == false)
        #expect(deps.entitlementFreeValue.plan == .free)
        #expect(deps.entitlementProValue.plan == .pro)
        #expect(deps.bookStateValue.completedChapterIds.isEmpty == false)
        #expect(deps.dashboardValue.currentStreak == 5)
        #expect(deps.streakValue.longestStreak == 12)
        #expect(deps.badgeItems.count == 4)
        #expect(deps.notebookEntries.count == 5)
        #expect(deps.reviewCards.count == 3)
        #expect(deps.notifications.count == 4)
        #expect(deps.conceptGraph.concepts.count == 6)
    }
}
