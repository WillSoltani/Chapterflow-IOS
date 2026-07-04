import Foundation
import Models
import Networking
import CoreKit

// MARK: - Closure-based API client for previews

/// A closure-driven `APIClientProtocol` for previews.
/// (Separate from `Networking.MockAPIClient` which is an actor with per-path stubs.)
final class PreviewAPIClient: APIClientProtocol, @unchecked Sendable {
    private let handler: @Sendable (Endpoint) async throws -> Data

    init(handler: @escaping @Sendable (Endpoint) async throws -> Data) {
        self.handler = handler
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

// MARK: - Preview fixtures

extension Dashboard {
    static let preview = Dashboard(
        currentStreak: 14,
        longestStreak: 21,
        todayReadingMinutes: 25,
        weeklyGoalMinutes: 120,
        weeklyReadMinutes: 85,
        booksStarted: 6,
        booksCompleted: 3,
        flowPoints: 1_250,
        tier: "analyst",
        tierProgress: 0.62,
        dueReviewCount: 8,
        continueBook: DashboardBookEntry(
            bookId: "atomic-habits",
            title: "Atomic Habits",
            lastChapterNumber: 7,
            cover: Cover(emoji: "⚡️", color: "#1A3B6E")
        )
    )
}

extension StreakState {
    static let preview = StreakState(
        currentStreak: 14,
        longestStreak: 21,
        streakShieldsHeld: 2,
        lastActivityDate: "2026-07-02",
        streakHistory: nil,
        consistencyLast30: Self.previewConsistencyDays(activeToday: true),
        milestonesReached: [7, 14]
    )

    static let previewAtRisk = StreakState(
        currentStreak: 5,
        longestStreak: 21,
        streakShieldsHeld: 1,
        lastActivityDate: "2026-07-01",
        streakHistory: nil,
        consistencyLast30: Self.previewConsistencyDays(activeToday: false),
        milestonesReached: []
    )

    static let previewNoStreak = StreakState(
        currentStreak: 0,
        longestStreak: 7,
        streakShieldsHeld: 0,
        lastActivityDate: nil,
        streakHistory: nil,
        consistencyLast30: [],
        milestonesReached: []
    )

    private static func previewConsistencyDays(activeToday: Bool) -> [StreakDay] {
        let base = [
            0, 18, 22, 0, 35, 15, 28, 0, 10, 40,
            25, 20, 30, 0, 45, 12, 8, 33, 0, 27,
            19, 42, 0, 15, 38, 24, 11, 0, 30, activeToday ? 25 : 0,
        ]
        return base.enumerated().map { index, minutes in
            // Compute date strings relative to 2026-07-02 (today in fixtures)
            let dayOffset = index - 29
            var comps = DateComponents()
            comps.year = 2026; comps.month = 7; comps.day = 2
            let base = Calendar.current.date(from: comps) ?? Date()
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: base) ?? base
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return StreakDay(date: f.string(from: date), minutesRead: minutes)
        }
    }
}

extension Array where Element == ProgressOverviewItem {
    static let preview: [ProgressOverviewItem] = [
        ProgressOverviewItem(bookId: "atomic-habits", currentChapterNumber: 7, totalChapters: 12, completedChapterCount: 7, lastReadAt: "2026-07-02T14:30:00Z"),
        ProgressOverviewItem(bookId: "deep-work", currentChapterNumber: 10, totalChapters: 10, completedChapterCount: 10, lastReadAt: "2026-06-28T09:00:00Z"),
        ProgressOverviewItem(bookId: "thinking-fast-and-slow", currentChapterNumber: 5, totalChapters: 14, completedChapterCount: 5, lastReadAt: "2026-06-20T18:00:00Z"),
        ProgressOverviewItem(bookId: "psychology-of-money", currentChapterNumber: 2, totalChapters: 20, completedChapterCount: 2, lastReadAt: "2026-06-15T10:00:00Z"),
        ProgressOverviewItem(bookId: "the-power-of-habit", currentChapterNumber: 12, totalChapters: 12, completedChapterCount: 12, lastReadAt: "2026-05-30T08:00:00Z"),
        ProgressOverviewItem(bookId: "essentialism", currentChapterNumber: 0, totalChapters: 15, completedChapterCount: 0, lastReadAt: nil),
    ]
}

extension Array where Element == BadgeItem {
    static let preview: [BadgeItem] = [
        // Mastery track — earned
        BadgeItem(badgeId: "m-first-chapter", name: "First Chapter", description: "Read your very first chapter.", category: "mastery", isEarned: true, earnedAt: "2026-05-10T09:00:00Z", icon: "📖"),
        BadgeItem(badgeId: "m-deep-thinker", name: "Deep Thinker", description: "Complete 5 books end-to-end.", category: "mastery", isEarned: true, earnedAt: "2026-06-15T14:30:00Z", icon: "🧠"),
        // Mastery track — locked with progress
        BadgeItem(badgeId: "m-polymath", name: "Polymath", description: "Complete 10 books across 5 categories.", category: "mastery", isEarned: false, earnedAt: nil, icon: "🎓", progress: 6, target: 10),
        BadgeItem(badgeId: "m-scholar", name: "Scholar", description: "Answer 500 quiz questions correctly.", category: "mastery", isEarned: false, earnedAt: nil, icon: "🔬", progress: 312, target: 500),

        // Consistency track — earned
        BadgeItem(badgeId: "c-7-day", name: "Week Warrior", description: "Maintain a 7-day reading streak.", category: "consistency", isEarned: true, earnedAt: "2026-06-01T08:00:00Z", icon: "🔥"),
        // Consistency track — locked with progress
        BadgeItem(badgeId: "c-30-day", name: "Monthly Master", description: "Maintain a 30-day reading streak.", category: "consistency", isEarned: false, earnedAt: nil, icon: "📅", progress: 14, target: 30),
        BadgeItem(badgeId: "c-100-day", name: "Centurion", description: "Maintain a 100-day reading streak.", category: "consistency", isEarned: false, earnedAt: nil, icon: "💯", progress: 14, target: 100),

        // Exploration track — earned
        BadgeItem(badgeId: "e-genre-hopper", name: "Genre Hopper", description: "Read books from 3 different categories.", category: "exploration", isEarned: true, earnedAt: "2026-06-20T11:00:00Z", icon: "🗺️"),
        // Exploration track — locked
        BadgeItem(badgeId: "e-world-reader", name: "World Reader", description: "Read books from 8 different categories.", category: "exploration", isEarned: false, earnedAt: nil, icon: "🌍", progress: 4, target: 8),

        // Hidden track — earned (reveal all details)
        BadgeItem(badgeId: "h-night-owl", name: "Night Owl", description: "Read past midnight 5 times.", category: "hidden", isEarned: true, earnedAt: "2026-06-28T00:15:00Z", icon: "🦉"),
        // Hidden track — locked (stay mysterious)
        BadgeItem(badgeId: "h-secret-1", name: "???", description: "Secret criteria.", category: "hidden", isEarned: false, earnedAt: nil, icon: nil),
        BadgeItem(badgeId: "h-secret-2", name: "???", description: "Secret criteria.", category: "hidden", isEarned: false, earnedAt: nil, icon: nil),
    ]
}

// MARK: - Flow Points fixtures

extension Array where Element == FlowLedgerEntry {
    static let preview: [FlowLedgerEntry] = [
        FlowLedgerEntry(id: "le-1", type: .earnDaily, amount: 50, description: "Daily reading goal", createdAt: "2026-07-03T08:00:00Z"),
        FlowLedgerEntry(id: "le-2", type: .earnQuiz, amount: 100, description: "Quiz passed: Atomic Habits Ch. 7", createdAt: "2026-07-02T20:15:00Z"),
        FlowLedgerEntry(id: "le-3", type: .earnStreak, amount: 75, description: "14-day streak bonus", createdAt: "2026-07-02T08:00:00Z"),
        FlowLedgerEntry(id: "le-4", type: .redeem, amount: -250, description: "Purchased: Bonus Book Unlock", createdAt: "2026-06-30T14:22:00Z"),
        FlowLedgerEntry(id: "le-5", type: .earnMilestone, amount: 200, description: "Milestone: 7 books started", createdAt: "2026-06-28T09:00:00Z"),
        FlowLedgerEntry(id: "le-6", type: .earnDaily, amount: 50, description: "Daily reading goal", createdAt: "2026-06-27T08:00:00Z"),
    ]
}

extension Array where Element == ShopItem {
    static let previewRewards: [ShopItem] = [
        ShopItem(id: "shop-1", kind: .bonusBookUnlock, name: "Bonus Book Unlock", description: "Add an extra book to your library beyond your free tier.", cost: 250, isOwned: false, isEquipped: nil, previewColor: nil),
        ShopItem(id: "shop-2", kind: .proPass7d, name: "7-Day Pro Pass", description: "Unlock all Pro features for one week.", cost: 1_500, isOwned: false, isEquipped: nil, previewColor: nil),
        ShopItem(id: "shop-3", kind: .proPass30d, name: "30-Day Pro Pass", description: "Unlock all Pro features for a full month.", cost: 5_000, isOwned: false, isEquipped: nil, previewColor: nil),
    ]

    static let previewCosmetics: [ShopItem] = [
        ShopItem(id: "theme-1", kind: .theme, name: "Midnight Blue", description: "Deep navy reading theme for late-night sessions.", cost: 500, isOwned: true, isEquipped: true, previewColor: "#1A3B6E"),
        ShopItem(id: "theme-2", kind: .theme, name: "Warm Sepia", description: "Classic sepia tones easy on the eyes.", cost: 400, isOwned: true, isEquipped: false, previewColor: "#C8A77E"),
        ShopItem(id: "frame-1", kind: .frame, name: "Gold Frame", description: "Elegant gold border for your profile.", cost: 300, isOwned: false, isEquipped: nil, previewColor: "#FFD700"),
        ShopItem(id: "season-1", kind: .seasonal, name: "Summer Splash", description: "Limited-time summer theme. ☀️", cost: 750, isOwned: false, isEquipped: nil, previewColor: "#FF8C00"),
    ]

    static let previewShopItems: [ShopItem] = previewRewards + previewCosmetics
}

// MARK: - TierState preview fixtures

extension TierState {
    static let previewAnalyst = TierState(
        currentTier: .analyst,
        nextTier: .synthesizer,
        overallProgress: 0.62,
        metrics: TierProgressDetail(
            loopsCompleted: 18,
            loopsTarget: 30,
            averageQuizScore: 74,
            quizScoreTarget: 80,
            categoriesExplored: 2,
            categoriesTarget: 3
        ),
        recentlyPromoted: false,
        previousTier: nil
    )

    static let previewLuminary = TierState(
        currentTier: .luminary,
        nextTier: nil,
        overallProgress: 1.0,
        metrics: nil,
        recentlyPromoted: false,
        previousTier: nil
    )

    static let previewReader = TierState(
        currentTier: .reader,
        nextTier: .analyst,
        overallProgress: 0.20,
        metrics: TierProgressDetail(
            loopsCompleted: 3,
            loopsTarget: 15,
            averageQuizScore: 65,
            quizScoreTarget: 70,
            categoriesExplored: 1,
            categoriesTarget: 2
        ),
        recentlyPromoted: false,
        previousTier: nil
    )

    static let previewPromoted = TierState(
        currentTier: .analyst,
        nextTier: .synthesizer,
        overallProgress: 0.05,
        metrics: TierProgressDetail(
            loopsCompleted: 1,
            loopsTarget: 30,
            averageQuizScore: 80,
            quizScoreTarget: 80,
            categoriesExplored: 2,
            categoriesTarget: 3
        ),
        recentlyPromoted: true,
        previousTier: .reader
    )
}

// MARK: - Preview EngagementRepository

extension EngagementRepository {
    /// An `EngagementRepository` pre-loaded with preview fixture data (no network, no disk).
    static var preview: EngagementRepository {
        makePreviewRepository(streak: .preview)
    }

    /// Repository where the streak has not been updated today (at-risk scenario).
    static var previewAtRisk: EngagementRepository {
        makePreviewRepository(streak: .previewAtRisk)
    }

    /// Repository where the user has no active streak.
    static var previewNoStreak: EngagementRepository {
        makePreviewRepository(streak: .previewNoStreak)
    }

    /// Repository pre-loaded with Analyst tier data for `TierView` previews.
    static var previewTierAnalyst: EngagementRepository {
        makeTierPreviewRepository(tier: .previewAnalyst)
    }

    /// Repository pre-loaded with Luminary tier data for `TierView` previews.
    static var previewTierLuminary: EngagementRepository {
        makeTierPreviewRepository(tier: .previewLuminary)
    }

    /// Repository pre-loaded with Reader tier data for `TierView` previews.
    static var previewTierReader: EngagementRepository {
        makeTierPreviewRepository(tier: .previewReader)
    }

    /// Repository that simulates a freshly promoted user for `TierView` previews.
    static var previewTierPromoted: EngagementRepository {
        makeTierPreviewRepository(tier: .previewPromoted)
    }

    private static func makePreviewRepository(streak: StreakState) -> EngagementRepository {
        let dashboard = Dashboard.preview
        let progress: [ProgressOverviewItem] = .preview
        let badges: [BadgeItem] = .preview
        let ledger: [FlowLedgerEntry] = .preview
        let shopItems: [ShopItem] = .previewShopItems
        let equipped = EquippedCosmetics(themeId: "theme-1", frameId: nil)
        let client = PreviewAPIClient { endpoint in
            switch endpoint.path {
            case "/book/me/dashboard":
                return try JSONCoding.encoder.encode(DashboardResponse(dashboard: dashboard))
            case "/book/me/streak":
                return try JSONCoding.encoder.encode(StreakResponse(streak: streak))
            case "/book/me/progress":
                return try JSONCoding.encoder.encode(ProgressOverviewResponse(progress: progress))
            case "/book/me/badges":
                return try JSONCoding.encoder.encode(BadgesResponse(badges: badges))
            case "/book/me/flow-points":
                return try JSONCoding.encoder.encode(
                    FlowPointsResponse(balance: dashboard.flowPoints, ledger: ledger, equippedCosmetics: equipped)
                )
            case "/book/me/shop":
                return try JSONCoding.encoder.encode(ShopResponse(items: shopItems))
            case "/book/me/flow-points/redeem":
                // Simulate a successful redeem: return updated balance and first shop item
                return try JSONCoding.encoder.encode(
                    RedeemFlowPointsResponse(balance: dashboard.flowPoints - 250, item: shopItems.first, equippedCosmetics: equipped)
                )
            case "/book/me/tier":
                return try JSONCoding.encoder.encode(TierResponse(tier: .previewAnalyst))
            default:
                throw AppError.notFound
            }
        }
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }

    private static func makeTierPreviewRepository(tier: TierState) -> EngagementRepository {
        let client = PreviewAPIClient { endpoint in
            switch endpoint.path {
            case "/book/me/tier":
                return try JSONCoding.encoder.encode(TierResponse(tier: tier))
            default:
                throw AppError.notFound
            }
        }
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - Preview FlowPointsModel

extension FlowPointsModel {
    /// Pre-loaded with fixture balance, ledger, and shop (no network).
    @MainActor static var preview: FlowPointsModel {
        FlowPointsModel(repository: .preview)
    }

    /// Empty ledger variant.
    @MainActor static var previewEmpty: FlowPointsModel {
        let client = PreviewAPIClient { endpoint in
            switch endpoint.path {
            case "/book/me/flow-points":
                return try JSONCoding.encoder.encode(
                    FlowPointsResponse(balance: 0, ledger: [], equippedCosmetics: nil)
                )
            case "/book/me/shop":
                return try JSONCoding.encoder.encode(ShopResponse(items: []))
            default:
                throw AppError.notFound
            }
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        return FlowPointsModel(repository: repo)
    }

    /// Starts on the Shop tab.
    @MainActor static var previewShop: FlowPointsModel {
        let model = FlowPointsModel(repository: .preview)
        model.selectedTab = .shop
        return model
    }
}

// MARK: - Preview BadgesModel

extension BadgesModel {
    /// A `BadgesModel` pre-loaded with fixture badges (no network, no disk).
    static var preview: BadgesModel {
        BadgesModel(repository: .preview, presenter: nil)
    }

    /// A `BadgesModel` in the error state for previewing the error UI.
    @MainActor static var previewError: BadgesModel {
        let model = BadgesModel(repository: .previewOffline, presenter: nil)
        return model
    }
}

extension EngagementRepository {
    /// An `EngagementRepository` that always throws `.offline` — for error previews.
    static var previewOffline: EngagementRepository {
        let client = PreviewAPIClient { _ in throw AppError.offline }
        return EngagementRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - AppError preview helper

extension AppError {
    static var preview: AppError { .offline }
}

// MARK: - Journey fixtures

extension JourneyCatalogItem {
    static let preview = JourneyCatalogItem(
        journeyId: "j-productivity",
        title: "Peak Productivity",
        description: "Build unbreakable focus and deep work habits through the lens of the best productivity thinkers.",
        durationWeeks: 6,
        books: [
            JourneyBookEntry(bookId: "deep-work", title: "Deep Work", author: "Cal Newport",
                             cover: Cover(emoji: "🎯", color: "#1A3B6E"),
                             reason: "The foundation — learn to do hard things without distraction.", order: 0),
            JourneyBookEntry(bookId: "atomic-habits", title: "Atomic Habits", author: "James Clear",
                             cover: Cover(emoji: "⚡️", color: "#2E5E2E"),
                             reason: "Turn tiny daily actions into compounding systems.", order: 1),
            JourneyBookEntry(bookId: "essentialism", title: "Essentialism", author: "Greg McKeown",
                             cover: Cover(emoji: "🎯", color: "#5E2E2E"),
                             reason: "Choose fewer, better things to focus on.", order: 2),
        ],
        completionBadge: JourneyBadge(badgeId: "journey-productivity", name: "Productivity Master", icon: "🏆"),
        bonusFlowPoints: 500,
        gradient: JourneyGradient(startColor: "#1A3B6E", endColor: "#2E5E2E")
    )
}

// MARK: - Preview JourneysRepository

extension JourneysRepository {
    static var preview: JourneysRepository {
        let journey = JourneyCatalogItem.preview
        let userJourney = UserJourney(
            journeyId: journey.journeyId,
            currentBookIndex: 1,
            completedBookIds: ["deep-work"],
            isCompleted: false,
            startedAt: "2026-06-01T10:00:00Z",
            completedAt: nil
        )
        let client = PreviewAPIClient { endpoint in
            if endpoint.path == "/book/books/journeys" {
                return try JSONCoding.encoder.encode(JourneysListResponse(journeys: [journey]))
            }
            if endpoint.path.hasPrefix("/book/me/journeys/") {
                return try JSONCoding.encoder.encode(UserJourneyResponse(journey: userJourney))
            }
            throw AppError.notFound
        }
        return JourneysRepository(apiClient: client, modelContainer: nil)
    }

    static var previewNotStarted: JourneysRepository {
        let journey = JourneyCatalogItem.preview
        let client = PreviewAPIClient { endpoint in
            if endpoint.path == "/book/books/journeys" {
                return try JSONCoding.encoder.encode(JourneysListResponse(journeys: [journey]))
            }
            if endpoint.path.hasPrefix("/book/me/journeys/"), endpoint.method == .post {
                let userJourney = UserJourney(
                    journeyId: journey.journeyId,
                    currentBookIndex: 0,
                    completedBookIds: [],
                    isCompleted: false,
                    startedAt: "2026-07-03T10:00:00Z",
                    completedAt: nil
                )
                return try JSONCoding.encoder.encode(UserJourneyResponse(journey: userJourney))
            }
            // Unenrolled: 404
            throw AppError.notFound
        }
        return JourneysRepository(apiClient: client, modelContainer: nil)
    }
}

// MARK: - Preview JourneysModel

extension JourneysModel {
    @MainActor static var preview: JourneysModel {
        JourneysModel(repository: .preview)
    }
}

// MARK: - Preview JourneyDetailModel

extension JourneyDetailModel {
    @MainActor static var previewNotStarted: JourneyDetailModel {
        JourneyDetailModel(
            journey: .preview,
            repository: .previewNotStarted,
            celebrationPresenter: CelebrationPresenter()
        )
    }

    @MainActor static var previewInProgress: JourneyDetailModel {
        let model = JourneyDetailModel(
            journey: .preview,
            repository: .preview,
            celebrationPresenter: CelebrationPresenter()
        )
        return model
    }
}

// MARK: - Scenario fixtures

extension UserScenario {
    static let previewPending = UserScenario(
        id: "s-001",
        bookId: "atomic-habits",
        chapterNumber: 3,
        title: "Building a morning writing habit",
        scenario: "I tend to check my phone first thing every morning, which derails my focus for the rest of the day. I want to use habit stacking to pair my coffee ritual with 15 minutes of writing.",
        whatToDo: "Place my notebook beside the coffee machine each night. When I pour my first cup, I sit at the table and write for exactly 15 minutes before touching my phone.",
        whyItMatters: "Writing first thing channels my freshest mental energy into creative work instead of reactive scrolling.",
        scope: .personal,
        status: .pending,
        pointsAwarded: nil,
        createdAt: Date(timeIntervalSinceNow: -3600)
    )

    static let previewApproved = UserScenario(
        id: "s-002",
        bookId: "atomic-habits",
        chapterNumber: 2,
        title: "Two-minute team stand-up rule",
        scenario: "Our remote stand-ups drag on because people check Slack between updates. I want to apply the two-minute rule to keep each person's update short and drive the meeting to under 10 minutes total.",
        whatToDo: "At the start of each stand-up, I'll remind the team: updates are two minutes max. I'll use a visible timer. Anything longer becomes a separate call.",
        whyItMatters: "Shorter stand-ups respect everyone's deep-work time and model the behaviour I want the team to adopt.",
        scope: .work,
        status: .approved,
        pointsAwarded: 50,
        createdAt: Date(timeIntervalSinceNow: -86400)
    )

    static let previewRejected = UserScenario(
        id: "s-003",
        bookId: "atomic-habits",
        chapterNumber: 1,
        title: "Using habits",
        scenario: "I want to use habits.",
        whatToDo: "Do the habits.",
        whyItMatters: "Habits are good.",
        scope: .school,
        status: .rejected,
        pointsAwarded: nil,
        createdAt: Date(timeIntervalSinceNow: -172800)
    )
}

extension CommunityScenario {
    static let previewCommunity1 = CommunityScenario(
        id: "cs-001",
        title: "Habit-stacking language learning",
        scenario: "I linked Spanish practice to my daily lunch break by listening to a podcast episode while I eat.",
        whatToDo: "Queue the podcast before sitting down for lunch. No podcast = no lunch (mild social contract with my roommate).",
        whyItMatters: "Language acquisition benefits from daily exposure, and lunch is the one consistent break in my day.",
        scope: .personal,
        authorName: "Alex K.",
        createdAt: Date(timeIntervalSinceNow: -43200)
    )
}

// MARK: - Preview ScenarioRepository

extension ScenarioRepository {
    static func makePreview(
        myScenarios: [UserScenario] = [.previewApproved, .previewPending, .previewRejected],
        community: [CommunityScenario] = [.previewCommunity1]
    ) -> ScenarioRepository {
        let resp = ScenariosResponse(scenarios: myScenarios, community: community)
        let previewScenario = UserScenario(
            id: "s-preview-new", bookId: "atomic-habits", chapterNumber: 3,
            title: "New scenario", scenario: "Preview scenario",
            whatToDo: "Do the thing", whyItMatters: "Because reasons",
            scope: .work, status: .pending, pointsAwarded: nil, createdAt: Date()
        )
        let client = PreviewAPIClient { endpoint in
            if endpoint.path.hasSuffix("/scenarios") && endpoint.method == .get {
                return try JSONCoding.encoder.encode(resp)
            }
            if endpoint.path.hasSuffix("/scenarios") && endpoint.method == .post {
                return try JSONCoding.encoder.encode(ScenarioResponse(scenario: previewScenario))
            }
            throw AppError.notFound
        }
        return ScenarioRepository(apiClient: client, modelContainer: nil)
    }

    static var previewEmpty: ScenarioRepository { makePreview(myScenarios: [], community: []) }
}

// MARK: - Preview ScenariosModel

extension ScenariosModel {
    @MainActor static var preview: ScenariosModel {
        ScenariosModel(
            repository: .makePreview(),
            bookId: "atomic-habits",
            chapterNumber: 3
        )
    }

    @MainActor static var previewEmpty: ScenariosModel {
        ScenariosModel(
            repository: .previewEmpty,
            bookId: "atomic-habits",
            chapterNumber: 3
        )
    }
}
