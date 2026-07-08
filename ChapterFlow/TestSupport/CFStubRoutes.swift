#if DEBUG
import Foundation

// swiftlint:disable line_length
/// Route table for ``CFStubURLProtocol``.
/// Maps URL path prefixes → (statusCode, JSON body) used by XCUITests.
enum CFStubRoutes {

    // MARK: - Lookup

    static func response(for path: String, method: String) -> (statusCode: Int, body: Data)? {
        for (route, handler) in routes {
            if path.hasPrefix(route.path) && (route.method == nil || route.method == method) {
                let body = handler().data(using: .utf8) ?? Data()
                return (200, body)
            }
        }
        return nil
    }

    // MARK: - Route table

    private struct Route: Hashable {
        let path: String
        let method: String?
    }

    private static let routes: [(Route, () -> String)] = [

        // ── Auth / identity ────────────────────────────────────────────────────
        (Route(path: "/auth/session", method: nil), { session }),
        (Route(path: "/me", method: nil), { me }),

        // ── Catalog ───────────────────────────────────────────────────────────
        (Route(path: "/book/books", method: "GET"), { catalog }),

        // ── Book detail / state ───────────────────────────────────────────────
        (Route(path: "/book/me/books/b-atomic-habits/start", method: "POST"), { emptyOK }),
        (Route(path: "/book/me/books/b-atomic-habits/state", method: nil), { bookState }),
        (Route(path: "/book/me/books/b-atomic-habits/chapters/1/state", method: nil), { emptyOK }),
        (Route(path: "/book/books/b-atomic-habits", method: nil), { bookManifest }),

        // ── Chapter ───────────────────────────────────────────────────────────
        (Route(path: "/book/books/b-atomic-habits/chapters/1", method: nil), { chapter }),
        (Route(path: "/book/books/b-atomic-habits/chapters/1/quiz", method: nil), { quiz }),

        // ── Quiz submission ───────────────────────────────────────────────────
        (Route(path: "/book/me/quiz/b-atomic-habits/1/submit", method: "POST"), { quizResult }),
        (Route(path: "/book/me/quiz/b-atomic-habits/1/check", method: "POST"), { checkResult }),
        (Route(path: "/book/me/quiz/b-atomic-habits/1/events", method: "POST"), { emptyOK }),

        // ── Chapter unlock ────────────────────────────────────────────────────
        (Route(path: "/book/me/chapters/b-atomic-habits/1/unlock", method: "POST"), { unlockOK }),

        // ── Progress ──────────────────────────────────────────────────────────
        (Route(path: "/book/me/progress", method: nil), { progress }),
        (Route(path: "/book/me/dashboard", method: nil), { dashboard }),
        (Route(path: "/book/me/streak", method: nil), { streak }),
        (Route(path: "/book/me/saved", method: nil), { savedBooks }),
        (Route(path: "/book/me/reviews", method: nil), { emptyReviews }),
        (Route(path: "/book/me/notifications", method: nil), { emptyNotifications }),

        // ── Reading session ───────────────────────────────────────────────────
        (Route(path: "/book/me/reading-sessions", method: "POST"), { emptyOK }),

        // ── Entitlement / billing ─────────────────────────────────────────────
        (Route(path: "/book/me/entitlements", method: "GET"), { entitlementFree }),
        (Route(path: "/book/me/billing/apple/verify", method: "POST"), { entitlementPro }),

        // ── Onboarding ───────────────────────────────────────────────────────
        (Route(path: "/book/me/onboarding", method: nil), { emptyOK }),

        // ── Search index ─────────────────────────────────────────────────────
        (Route(path: "/book/search-index", method: nil), { emptyOK }),

        // ── Core Spotlight / analytics ───────────────────────────────────────
        (Route(path: "/book/me/analytics", method: nil), { emptyOK }),
        (Route(path: "/book/me/devices", method: nil), { emptyOK }),

        // ── Settings ─────────────────────────────────────────────────────────
        (Route(path: "/book/me/settings", method: nil), { settings }),
    ]

    // MARK: - Response bodies

    private static let session = """
    {"loggedIn":true,"user":{"sub":"uitest-user-123","email":"test@chapterflow.com"}}
    """

    private static let me = """
    {"sub":"uitest-user-123","email":"test@chapterflow.com","displayName":"Test User"}
    """

    private static let catalog = """
    {"books":[{"bookId":"b-atomic-habits","title":"Atomic Habits","author":"James Clear","categories":["Productivity"],"tags":["habits"],"cover":{"emoji":"⚛️","color":"#2D6A4F"},"variantFamily":"EMH","status":"published","latestVersion":3,"currentPublishedVersion":3,"updatedAt":"2024-01-15T10:00:00.000Z"},{"bookId":"b-deep-work","title":"Deep Work","author":"Cal Newport","categories":["Productivity"],"tags":["focus"],"cover":{"emoji":"🎯","color":"#1B4332"},"variantFamily":"PBC","status":"published","latestVersion":2,"currentPublishedVersion":2,"updatedAt":"2024-02-01T09:00:00.000Z"}]}
    """

    private static let bookState = """
    {"state":{"bookId":"b-atomic-habits","currentChapterNumber":1,"currentChapterId":"ch-ah-1","completedChapterIds":[],"unlockedChapterIds":["ch-ah-1"],"chapterScores":{},"lastReadChapterId":null},"applicationStates":{}}
    """

    private static let bookManifest = """
    {"bookId":"b-atomic-habits","title":"Atomic Habits","author":"James Clear","cover":{"emoji":"⚛️","color":"#2D6A4F"},"categories":["Productivity"],"tags":["habits"],"variantFamily":"EMH","status":"published","latestVersion":3,"currentPublishedVersion":3,"updatedAt":"2024-01-15T10:00:00.000Z","chapters":[{"chapterId":"ch-ah-1","number":1,"title":"The Surprising Power of Atomic Habits","readingTimeMinutes":20,"isPreview":false},{"chapterId":"ch-ah-2","number":2,"title":"How Habits Shape Your Identity","readingTimeMinutes":18,"isPreview":false}],"chapterCount":2,"totalReadingTimeMinutes":38}
    """

    private static let chapter = """
    {"chapter":{"chapterId":"ch-ah-1","number":1,"title":"The Surprising Power of Atomic Habits","readingTimeMinutes":20,"activeVariant":"medium","availableVariants":["easy","medium","hard"],"contentVariants":{"medium":{"chapterBreakdown":{"gentle":"Small habits compound remarkably over time.","direct":"1% improvements compound to 37× gains over a year.","competitive":"Master the art of marginal gains to dominate your field."},"keyTakeaways":[{"point":{"gentle":"Small changes lead to big results.","direct":"1% daily improvement compounds to 37× gains.","competitive":"Marginally superior habits create exponentially better outcomes."}}],"oneMinuteRecap":{"gentle":"Habits matter more than you think.","direct":"1% improvements compound dramatically over time.","competitive":"Your habits are your competitive edge."},"activationPrompt":{"gentle":"What small habit could you improve today?","direct":"Identify one habit to improve by 1% this week.","competitive":"Which habit gives you the biggest competitive edge right now?"},"selfCheckPrompts":["Can you name one habit you could improve by 1%?","How do small improvements compound over time?"],"reflectionPrompts":["What tiny change could transform your performance?","Where are you accepting mediocrity in your daily habits?"]}},"examples":[],"implementationPlan":null,"reviewCards":[{"cardId":"card-1","front":"What happens when you improve 1% every day for a year?","back":{"gentle":"You become 37× better.","direct":"37× improvement through compounding.","competitive":"37× gains — the compound effect of marginal superiority."}}],"keyTakeawayCard":{"cardId":"ktc-1","front":"The core insight of Atomic Habits","back":{"gentle":"Small habits matter enormously over time.","direct":"1% better every day = 37× better in a year.","competitive":"Marginal daily gains compound into massive competitive advantages."}},"v21Extras":null},"progress":{"progressRev":1,"currentChapterNumber":1,"unlockedThroughChapterNumber":1,"completedChapters":[],"bestScoreByChapter":{},"preferredVariant":"medium"}}
    """

    private static let quiz = """
    {"quiz":{"sessionId":"session-uitest-1","bookId":"b-atomic-habits","chapterNumber":1,"questions":[{"questionId":"q1","prompt":"What is the result of improving 1% every day for a year?","choices":[{"choiceId":"c1a","text":"You become approximately 37× better"},{"choiceId":"c1b","text":"You improve by 365%"},{"choiceId":"c1c","text":"You double your performance"},{"choiceId":"c1d","text":"You improve by 100%"}]},{"questionId":"q2","prompt":"What does the book call the accumulation of tiny 1% improvements?","choices":[{"choiceId":"c2a","text":"The aggregation of marginal gains"},{"choiceId":"c2b","text":"The compound effect"},{"choiceId":"c2c","text":"The habit loop"},{"choiceId":"c2d","text":"Kaizen"}]}]},"progress":{"progressRev":1,"currentChapterNumber":1,"unlockedThroughChapterNumber":1,"completedChapters":[],"bestScoreByChapter":{},"preferredVariant":"medium"}}
    """

    private static let quizResult = """
    {"passed":true,"scorePercent":100,"questionResults":[{"questionId":"q1","correctChoiceId":"c1a","isCorrect":true},{"questionId":"q2","correctChoiceId":"c2a","isCorrect":true}],"cooldownSeconds":0,"nextEligibleAttemptAt":null,"unlockedNextChapter":true}
    """

    private static let checkResult = """
    {"questionId":"q1","isCorrect":true,"correctChoiceId":"c1a"}
    """

    private static let unlockOK = """
    {"unlocked":true,"chapterNumber":2}
    """

    private static let progress = """
    {"books":[{"bookId":"b-atomic-habits","currentChapterNumber":1,"unlockedThroughChapterNumber":1,"completedChapters":[],"bestScoreByChapter":{},"progressRev":1}]}
    """

    private static let dashboard = """
    {"streakDays":3,"totalBooksCompleted":0,"totalChaptersCompleted":0,"totalReadingTimeMinutes":45,"flowPoints":120,"currentTier":"Explorer","recentActivity":[]}
    """

    private static let streak = """
    {"currentStreak":3,"longestStreak":7,"lastStreakDate":"2024-01-15T00:00:00.000Z","streakGoal":7,"todayCompleted":false}
    """

    private static let savedBooks = """
    {"saved":[]}
    """

    private static let emptyReviews = """
    {"reviews":[],"nextDueAt":null}
    """

    private static let emptyNotifications = """
    {"notifications":[]}
    """

    private static let entitlementFree = """
    {"entitlement":{"plan":"FREE","proStatus":null,"proSource":null,"freeBookSlots":2,"unlockedBookIds":["b-atomic-habits"],"unlockedBooksCount":1,"remainingFreeStarts":1,"currentPeriodEnd":null,"cancelAtPeriodEnd":null,"licenseKey":null,"licenseExpiresAt":null},"paywall":{"price":"$9.99/month","pricingTiers":[{"id":"pro_monthly","name":"Monthly","price":"$9.99","period":"month","isPopular":false},{"id":"pro_annual","name":"Annual","price":"$79.99","period":"year","isPopular":true}],"benefits":["Unlimited books","All depth variants","Priority support"]}}
    """

    private static let entitlementPro = """
    {"entitlement":{"plan":"PRO","proStatus":"active","proSource":"apple","freeBookSlots":999,"unlockedBookIds":[],"unlockedBooksCount":0,"remainingFreeStarts":999,"currentPeriodEnd":"2027-01-01T00:00:00Z","cancelAtPeriodEnd":false,"licenseKey":null,"licenseExpiresAt":null},"paywall":null}
    """

    private static let settings = """
    {"tone":"direct","depthVariant":"medium","notificationsEnabled":true,"reminderTime":"09:00","timezone":"America/Toronto"}
    """

    private static let emptyOK = """
    {}
    """
}
// swiftlint:enable line_length
#endif
