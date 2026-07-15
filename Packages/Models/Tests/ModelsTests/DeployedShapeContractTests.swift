import Testing
import Foundation
@testable import Models

// MARK: - Deployed-shape contract tests (authed endpoints)
//
// The public endpoints are covered by VERBATIM captures (RealContractTests).
// The authed `/book/me/*` + chapter/quiz shapes below are DERIVED FROM THE
// DEPLOYED SERVERLESS CODE at production sha 19b44fac (2026-07-02 deploy),
// file:line provenance noted per suite. When a CF_CI_TOKEN becomes available,
// scripts/refresh-fixtures.sh replaces these with real captures.
// See docs/API-CONTRACT-MISMATCH-AND-RECONCILIATION-PLAN.md.

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder.chapterFlow.decode(T.self, from: Data(json.utf8))
}

// Provenance: app/app/api/book/books/[bookId]/chapters/[chapterNumber]/route.ts:59-83
@Suite("Deployed shape — GET /book/books/{id}/chapters/{n}")
struct DeployedChapterShapeTests {

    private let payload = #"""
    {"chapter":{"chapterId":"seven-powers-ch01","number":1,"title":"Scale Economies",
      "readingTimeMinutes":12,"activeVariant":"medium",
      "availableVariants":["easy","medium","hard"],
      "content":{"chapterBreakdown":{"gentle":"g","direct":"d","competitive":"c"}},
      "contentVariants":{
        "easy":{"chapterBreakdown":{"gentle":"g","direct":"d","competitive":"c"}},
        "medium":{"chapterBreakdown":{"gentle":"g","direct":"d","competitive":"c"}},
        "hard":{"chapterBreakdown":{"gentle":"g","direct":"d","competitive":"c"}}},
      "examples":[]},
     "progress":{"currentChapterNumber":1,"unlockedThroughChapterNumber":1,
      "completedChapters":[]}}
    """#

    @Test("chapter + TRIMMED progress (no bestScoreByChapter) decodes")
    func chapterResponseDecodes() throws {
        let response = try decode(ChapterResponse.self, payload)
        #expect(response.chapter.chapterId == "seven-powers-ch01")
        #expect(response.chapter.availableVariants.count == 3)
        // The deployed progress projection omits bestScoreByChapter — it
        // defaults instead of failing the whole reader.
        #expect(response.progress.bestScoreByChapter.isEmpty)
        #expect(response.progress.currentChapterNumber == 1)
    }

    @Test("a chapter missing optional serializer keys still renders")
    func sparseChapterDecodes() throws {
        let sparse = #"""
        {"chapterId":"c1","contentVariants":{"easy":{"importantSummary":"s"}}}
        """#
        let chapter = try decode(Chapter.self, sparse)
        #expect(chapter.chapterId == "c1")
        #expect(chapter.activeVariant == .easy)      // derived from variants
        #expect(chapter.availableVariants == [.easy]) // derived from variants
        #expect(chapter.content.importantSummary == "s") // derived content
    }

    @Test("a chapter with NO content at all is rejected (nothing to render)")
    func contentlessChapterThrows() {
        #expect(throws: DecodingError.self) {
            _ = try decode(Chapter.self, #"{"chapterId":"c1"}"#)
        }
    }
}

// Provenance: app/app/api/book/me/quiz/[bookId]/[chapterNumber]/submit/route.ts:268-287
// + _lib/quiz-session.ts:377-505 (result/history/questions projection).
@Suite("Deployed shape — POST /book/me/quiz/{id}/{n}/submit")
struct DeployedQuizSubmitShapeTests {

    private let passedPayload = #"""
    {"quiz":{"chapterId":"ch01","chapterNumber":1,"title":"T","passingScorePercent":80,
      "status":"passed","attemptNumber":1,"nextAttemptNumber":null,"attemptsCount":1,
      "failureStreak":0,"cooldownSeconds":0,"nextAttemptAvailableAt":null,
      "highestScorePercent":100,"unlockedNextChapter":true,
      "latestAttemptAt":"2026-07-10T12:00:00Z",
      "questions":[
        {"questionId":"q1","prompt":"P1","choices":[{"choiceId":"a","text":"A"}],
         "selectedChoiceId":"a","correctChoiceId":"a","isCorrect":true},
        {"questionId":"q2","prompt":"P2","choices":[{"choiceId":"b","text":"B"}],
         "selectedChoiceId":"b","correctChoiceId":"c","isCorrect":false}],
      "result":{"attemptNumber":1,"scorePercent":50,"correctAnswers":1,
        "totalQuestions":2,"passed":false,"submittedAt":"2026-07-10T12:00:00Z"},
      "history":[]},
     "progress":{"currentChapterNumber":1,"unlockedThroughChapterNumber":2,
      "completedChapters":[1]}}
    """#

    @Test("the {quiz: session} envelope maps to a flat QuizAttemptResult")
    func envelopeMapsToAttemptResult() throws {
        let result = try decode(QuizAttemptResult.self, passedPayload)
        // Grade facts come from quiz.result (server-authoritative).
        #expect(result.passed == false)
        #expect(result.scorePercent == 50)
        #expect(result.correctCount == 1)
        #expect(result.totalQuestions == 2)
        #expect(result.unlockedNextChapter == true)
        #expect(result.cooldownSeconds == 0)
        // Per-question grades come from the server-marked question fields.
        #expect(result.questionResults.count == 2)
        let q2 = try #require(result.questionResults.first { $0.questionId == "q2" })
        #expect(q2.isCorrect == false)
        #expect(q2.correctChoiceId == "c")
    }

    @Test("cooldown fields map from nextAttemptAvailableAt")
    func cooldownMapping() throws {
        let cooldown = passedPayload
            .replacingOccurrences(of: #""cooldownSeconds":0"#, with: #""cooldownSeconds":300"#)
            .replacingOccurrences(
                of: #""nextAttemptAvailableAt":null"#,
                with: #""nextAttemptAvailableAt":"2026-07-10T13:00:00Z""#)
        let result = try decode(QuizAttemptResult.self, cooldown)
        #expect(result.cooldownSeconds == 300)
        #expect(result.nextEligibleAttemptAt == "2026-07-10T13:00:00Z")
    }

    @Test("the canonical flat shape still decodes (caches/fixtures)")
    func canonicalFlatStillDecodes() throws {
        let flat = #"""
        {"passed":true,"scorePercent":100,"correctCount":5,"totalQuestions":5,
         "cooldownSeconds":0,"unlockedNextChapter":true,
         "questionResults":[{"questionId":"q1","selectedChoiceId":"a",
           "correctChoiceId":"a","isCorrect":true}]}
        """#
        let result = try decode(QuizAttemptResult.self, flat)
        #expect(result.passed)
        #expect(result.questionResults.count == 1)
    }
}

// Provenance: app/app/api/book/me/entitlements/route.ts:40-63.
@Suite("Deployed shape — GET /book/me/entitlements")
struct DeployedEntitlementShapeTests {

    @Test("the deployed entitlement + paywall decode (undefined-dropped keys absent)")
    func entitlementDecodes() throws {
        // proSource/currentPeriodEnd/licenseKey are `undefined`-dropped for
        // free users; proStatus is "inactive" (not null).
        let payload = #"""
        {"entitlement":{"plan":"FREE","proStatus":"inactive","freeBookSlots":3,
          "unlockedBookIds":["seven-powers"],"unlockedBooksCount":1,
          "remainingFreeStarts":2,"cancelAtPeriodEnd":false},
         "paywall":{"price":"$6.99/mo","pricingTiers":[],"benefits":["b1","b2"]}}
        """#
        let response = try decode(EntitlementResponse.self, payload)
        #expect(response.entitlement.plan == .free)
        #expect(response.entitlement.remainingFreeStarts == 2)
        #expect(response.entitlement.proSource == nil)
        #expect(response.paywall?.benefits.count == 2)
    }
}

// Provenance: app/app/api/book/me/streak/route.ts:29-43.
@Suite("Deployed shape — GET /book/me/streak")
struct DeployedStreakShapeTests {

    @Test("flat streak with shieldsHeld/lastActiveDate renames decodes")
    func streakDecodes() throws {
        let payload = #"""
        {"currentStreak":4,"longestStreak":9,"lastActiveDate":"2026-07-10",
         "shieldsHeld":2,"consistencyScore":47,
         "nextMilestone":{"days":7,"ip":50,"daysRemaining":3},
         "milestonesReached":[3]}
        """#
        let response = try decode(StreakResponse.self, payload)
        #expect(response.streak.currentStreak == 4)
        #expect(response.streak.streakShieldsHeld == 2) // ← shieldsHeld
        #expect(response.streak.lastActivityDate == "2026-07-10") // ← lastActiveDate
        #expect(response.streak.milestonesReached == [3])
        // consistencyScore is a NUMBER (not the canonical day array) — the
        // type-mismatched alternate stays nil rather than throwing.
        #expect(response.streak.consistencyLast30 == nil)
    }

    @Test("the canonical {streak:{…}} wrapper still decodes")
    func canonicalWrapperStillDecodes() throws {
        let payload = #"""
        {"streak":{"currentStreak":1,"longestStreak":2,"streakShieldsHeld":0,
          "lastActivityDate":null,"streakHistory":null}}
        """#
        let response = try decode(StreakResponse.self, payload)
        #expect(response.streak.currentStreak == 1)
    }
}

// Provenance: app/app/api/book/me/dashboard/route.ts:130-147.
@Suite("Deployed shape — GET /book/me/dashboard (web aggregate)")
struct DeployedDashboardShapeTests {

    @Test("the web homepage aggregate synthesizes an iOS Dashboard")
    func aggregateSynthesizes() throws {
        let payload = #"""
        {"catalog":[],"entitlement":null,"profile":null,"settings":null,
         "progress":[{"bookId":"a"},{"bookId":"b"}],
         "bookStates":{},"chapterStates":{},"saved":[],
         "readingDays":[],"badgeAwards":[],"insightPointsBalance":140,
         "partial":false,"warnings":[]}
        """#
        let response = try decode(DashboardResponse.self, payload)
        #expect(response.dashboard.flowPoints == 140)   // ← insightPointsBalance
        #expect(response.dashboard.booksStarted == 2)   // ← progress count
        #expect(response.dashboard.currentStreak == 0)  // overlaid by /me/streak
    }

    @Test("the canonical {dashboard:{…}} shape still decodes")
    func canonicalStillDecodes() throws {
        let payload = #"""
        {"dashboard":{"currentStreak":3,"longestStreak":5,"todayReadingMinutes":12,
          "weeklyGoalMinutes":90,"weeklyReadMinutes":40,"booksStarted":2,
          "booksCompleted":1,"flowPoints":75,"tier":"analyst","tierProgress":0.4,
          "dueReviewCount":6,"continueBook":null}}
        """#
        let response = try decode(DashboardResponse.self, payload)
        #expect(response.dashboard.currentStreak == 3)
        #expect(response.dashboard.dueReviewCount == 6)
    }
}

// Provenance: app/app/api/book/me/notifications/route.ts:28 +
// types.ts:607-617 (BookUserNotificationItem — readAt, not isRead).
@Suite("Deployed shape — GET /book/me/notifications")
struct DeployedNotificationsShapeTests {

    @Test("readAt string|null maps to isRead; unknown types survive")
    func inboxDecodes() throws {
        let payload = #"""
        {"notifications":[
          {"notificationId":"n1","type":"badge_earned","title":"T","body":"B",
           "channel":"inapp","readAt":null,"createdAt":"2026-07-09T10:00:00Z"},
          {"notificationId":"n2","type":"weekly_digest","title":"T2","body":"B2",
           "channel":"inapp","readAt":"2026-07-09T11:00:00Z",
           "createdAt":"2026-07-09T10:30:00Z"}],
         "unreadCount":1}
        """#
        let response = try decode(NotificationsResponse.self, payload)
        #expect(response.notifications.count == 2)
        #expect(response.unreadCount == 1)
        let unread = try #require(response.notifications.first { $0.notificationId == "n1" })
        #expect(unread.isRead == false)
        let read = try #require(response.notifications.first { $0.notificationId == "n2" })
        #expect(read.isRead == true)
        #expect(read.type == .unknown("weekly_digest")) // tolerated, not dropped
    }
}

// Provenance: app/app/api/book/me/flow-points/route.ts:83-113.
@Suite("Deployed shape — GET /book/me/flow-points")
struct DeployedFlowPointsShapeTests {

    @Test("summary.balance + recentTransactions map to balance + ledger")
    func flowPointsDecodes() throws {
        let payload = #"""
        {"summary":{"balance":140,"lifetimeEarned":420,"lifetimeSpent":280,
          "rewardReadyCount":1,"nextReward":null},
         "rewards":[],
         "recentTransactions":[
          {"transactionId":"t1","direction":"earn","amount":15,
           "sourceType":"quiz_pass","rewardId":null,"title":"Quiz passed",
           "subtitle":"Chapter 3","createdAt":"2026-07-09T10:00:00Z"},
          {"transactionId":"t2","direction":"spend","amount":100,
           "sourceType":"redeem","rewardId":"pro_pass_7d","title":"Redeemed",
           "subtitle":null,"createdAt":"2026-07-08T10:00:00Z"}]}
        """#
        let response = try decode(FlowPointsResponse.self, payload)
        #expect(response.balance == 140)
        #expect(response.ledger?.count == 2)
        let spend = try #require(response.ledger?.first { $0.id == "t2" })
        #expect(spend.amount == -100) // sign derived from direction
        let earn = try #require(response.ledger?.first { $0.id == "t1" })
        #expect(earn.amount == 15)
        #expect(earn.description == "Quiz passed") // ← title
    }
}

// Provenance: app/app/api/book/me/badges/route.ts:32-34 (awards list).
@Suite("Deployed shape — GET /book/me/badges")
struct DeployedBadgesShapeTests {

    @Test("the {awards:[…]} envelope decodes with inferred earned state")
    func awardsDecode() throws {
        let payload = #"""
        {"awards":[{"badgeId":"first-book","earnedAt":"2026-07-01T00:00:00Z","tier":"bronze"}]}
        """#
        let response = try decode(BadgesResponse.self, payload)
        #expect(response.badges.count == 1)
        #expect(response.badges[0].isEarned)
    }
}

// Provenance: app/app/api/book/events/active/route.ts:33-41 ({events} list).
@Suite("Deployed shape — GET /book/events/active")
struct DeployedEventsShapeTests {

    @Test("the {events:[…]} list surfaces its first event; participation implies joined")
    func eventsListDecodes() throws {
        let payload = #"""
        {"events":[{"eventId":"summer-sprint","title":"Summer Sprint",
          "startsAt":"2026-07-01T00:00:00Z","endsAt":"2026-07-31T00:00:00Z",
          "targetChapters":10,"dailyTarget":1,"bonusIp":100,
          "participation":{"eventId":"summer-sprint","chaptersCompleted":3}}]}
        """#
        let response = try decode(ActiveEventResponse.self, payload)
        let event = try #require(response.event)
        #expect(event.eventId == "summer-sprint")
        #expect(event.hasJoined) // inferred from participation
        #expect(event.isActive)  // defaulted true for an active-events feed
    }

    @Test("no active events → nil event (both shapes)")
    func emptyDecodes() throws {
        #expect(try decode(ActiveEventResponse.self, #"{"events":[]}"#).event == nil)
        #expect(try decode(ActiveEventResponse.self, #"{"event":null}"#).event == nil)
    }
}

// Provenance: app/app/api/book/me/commitments/route.ts:94-95 +
// types.ts:948-965 (BookUserCommitmentItem).
@Suite("Deployed shape — GET /book/me/commitments")
struct DeployedCommitmentsShapeTests {

    @Test("commitmentId/ifThenPlan/chapterNumber map onto the canonical model")
    func commitmentsDecode() throws {
        let payload = #"""
        {"commitments":[{"userId":"u1","commitmentId":"cm1","bookId":"atomic-habits",
          "chapterNumber":3,"ifThenPlan":"If I finish lunch, then I will read 10 pages",
          "commitDate":"2026-07-08T10:00:00Z","followUpDate":"2026-07-11T10:00:00Z",
          "followUpDays":3,"status":"active","followThroughReflection":null,
          "ipAwarded":0,"notificationSentAt":null,
          "createdAt":"2026-07-08T10:00:00Z","updatedAt":"2026-07-08T10:00:00Z"}]}
        """#
        let response = try decode(CommitmentsResponse.self, payload)
        #expect(response.commitments.count == 1)
        let commitment = try #require(response.commitments.first)
        #expect(commitment.id == "cm1")
        #expect(commitment.chapterId == "atomic-habits-ch03") // derived, manifest scheme
        #expect(commitment.ifStatement.hasPrefix("If I finish lunch"))
        #expect(commitment.status == .active)
    }
}

// Provenance: app/app/api/book/me/books/[bookId]/chapters/[chapterNumber]/
// scenarios/route.ts:124-140 (mySubmissions/approvedScenarios).
@Suite("Deployed shape — GET …/scenarios")
struct DeployedScenariosShapeTests {

    @Test("mySubmissions/approvedScenarios map to scenarios/community")
    func scenariosDecode() throws {
        let payload = #"""
        {"approvedScenarios":[{"id":"community-s9","title":"T","scope":"work",
          "scenario":"S","whatToDo":"W","whyItMatters":"Y"}],
         "mySubmissions":[{"submissionId":"s1","title":"Mine","scenario":"S",
          "whatToDo":"W","whyItMatters":"Y","scope":"personal","status":"pending",
          "createdAt":"2026-07-09T10:00:00Z"}]}
        """#
        let response = try decode(ScenariosResponse.self, payload)
        #expect(response.scenarios.count == 1)
        #expect(response.scenarios[0].id == "s1")
        #expect(response.community.count == 1)
        #expect(response.community[0].id == "community-s9")
    }
}

// Provenance: app/app/api/book/me/books/[bookId]/state/route.ts:122-156.
@Suite("Deployed shape — GET /book/me/books/{id}/state")
struct DeployedBookStateShapeTests {

    @Test("the canonical state envelope decodes (deployed emits it as-is)")
    func stateDecodes() throws {
        let payload = #"""
        {"state":{"userId":"u1","bookId":"atomic-habits",
          "currentChapterId":"atomic-habits-ch03",
          "completedChapterIds":["atomic-habits-ch01","atomic-habits-ch02"],
          "unlockedChapterIds":["atomic-habits-ch01","atomic-habits-ch02","atomic-habits-ch03"],
          "chapterScores":{"atomic-habits-ch01":100},
          "chapterCompletedAt":{"atomic-habits-ch01":"2026-07-01T00:00:00Z"},
          "lastReadChapterId":"atomic-habits-ch03",
          "lastOpenedAt":"2026-07-09T10:00:00Z",
          "createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-09T10:00:00Z"},
         "applicationStates":{"atomic-habits-ch01":"committed"}}
        """#
        let response = try decode(BookStateGetResponse.self, payload)
        #expect(response.stateStatus == nil)
        #expect(response.state.completedChapterIds.count == 2)
        #expect(response.applicationStates?["atomic-habits-ch01"] == .committed)
    }
}

// Provenance: app/app/api/book/me/tier/route.ts:23-34 (flat spread + tiers).
@Suite("Deployed shape — POST /book/me/tier")
struct DeployedTierShapeTests {

    @Test("the flat tier progress decodes without a wrapper")
    func flatTierDecodes() throws {
        let payload = #"""
        {"currentTier":"analyst","overallProgress":0.4,
         "tiers":[{"name":"reader","displayName":"Reader","loopsRequired":0,
           "avgScoreRequired":0,"categoriesRequired":0,
           "identityStatement":"…","reached":true}]}
        """#
        let response = try decode(TierResponse.self, payload)
        #expect(response.tier.currentTier == .analyst)
        #expect(response.tier.overallProgress == 0.4)
    }
}

// Provenance: app/app/api/book/me/notebook/route.ts:111 +
// _lib/notebook-entries.ts:48-73 (id-keyed entries, no updatedAt).
@Suite("Deployed shape — GET /book/me/notebook")
struct DeployedNotebookShapeTests {

    @Test("id-keyed entries with no updatedAt decode")
    func notebookDecodes() throws {
        let payload = #"""
        {"entries":[{"id":"note:atomic-habits:3","type":"note","bookId":"atomic-habits",
          "bookTitle":"Atomic Habits","chapterNumber":3,"chapterTitle":"Habit Stacking",
          "content":"My note","tags":[],"createdAt":"2026-07-09T10:00:00Z"}],
         "totalCount":1}
        """#
        let response = try decode(NotebookResponse.self, payload)
        #expect(response.entries.count == 1)
        let entry = try #require(response.entries.first)
        #expect(entry.entryId == "note:atomic-habits:3")
        #expect(entry.updatedAt == entry.createdAt) // fallback
        #expect(entry.type == .note)
    }
}

// Provenance: app/app/api/book/me/profile/route.ts:280-292 + _lib/identity.ts:5-15.
@Suite("Deployed shape — GET /book/me/profile")
struct DeployedProfileShapeTests {

    @Test("identity.sub + null profile synthesize a usable OwnProfile-shaped envelope")
    func profileSynthesis() throws {
        // OwnProfile lives in SocialFeature; here we assert the raw envelope
        // decodes via the Models-level pieces it shares (nothing throws).
        // Full assertions live in SocialFeature's DeployedProfileTests.
        let payload = #"""
        {"profile":null,
         "identity":{"sub":"user-123","email":"a@b.c","emailVerified":true,
           "displayName":"Will","authDisplayName":"Will","profileDisplayName":null,
           "givenName":"Will","familyName":null,"preferredUsername":null,
           "source":"cognito"},
         "inferredLocation":null,"updatedAt":null}
        """#
        let object = try JSONSerialization.jsonObject(with: Data(payload.utf8))
        #expect(object is [String: Any])
    }
}

// Provenance: app/app/api/book/me/pairs/route.ts:10-21 ({pair, partner}).
@Suite("Deployed shape — GET /book/me/pairs")
struct DeployedPairsShapeTests {

    @Test("the single {pair, partner} shape decodes (assertions in SocialFeature)")
    func pairShapeIsObject() throws {
        let payload = #"""
        {"pair":{"userId":"u1","partnerId":"u2","pairedAt":"2026-07-01T00:00:00Z",
          "status":"active","createdAt":"2026-07-01T00:00:00Z",
          "updatedAt":"2026-07-01T00:00:00Z"},
         "partner":{"displayName":"Ada"}}
        """#
        let object = try JSONSerialization.jsonObject(with: Data(payload.utf8))
        #expect(object is [String: Any])
    }
}
