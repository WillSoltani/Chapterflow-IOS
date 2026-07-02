import Models

/// A container of pre-decoded fixture data that powers SwiftUI `#Preview`s and
/// unit tests without any network access.
///
/// Feature packages inject this via their preview provider:
///
/// ```swift
/// #Preview {
///     let deps = PreviewDependencies.shared
///     LibraryView(books: deps.books, entitlement: deps.entitlementFreeValue)
/// }
/// ```
///
/// The `shared` singleton is the default for previews. Create a custom instance
/// with overridden properties when a test needs specific state (e.g. a PRO user).
public struct PreviewDependencies: Sendable {

    // MARK: - Catalog

    public let books: [BookCatalogItem]
    public let bookManifest: BookManifest

    // MARK: - Chapters

    /// EMH chapter (Atomic Habits ch.1) with v21Extras populated.
    public let chapterEMH: ChapterResponse
    /// PBC chapter (Deep Work ch.1) with v21Extras = nil.
    public let chapterPBC: ChapterResponse
    /// Resolved EMH chapter at `.medium` / `.direct`.
    public let resolvedEMH: ResolvedChapter
    /// Resolved PBC chapter at `.balanced` / `.gentle`.
    public let resolvedPBC: ResolvedChapter

    // MARK: - Quiz

    public let quizSession: QuizResponse
    public let quizResultPassed: QuizAttemptResult
    public let quizResultFailed: QuizAttemptResult

    // MARK: - Entitlement

    public let entitlementFree: EntitlementResponse
    public let entitlementPro: EntitlementResponse

    // MARK: - Book state

    public let bookState: BookStateResponse

    // MARK: - Engagement

    public let dashboard: DashboardResponse
    public let streak: StreakResponse
    public let badges: BadgesResponse
    public let notebook: NotebookResponse
    public let reviews: ReviewsResponse

    // MARK: - Notifications

    public let notificationsResponse: NotificationsResponse

    // MARK: - Concept graph

    public let conceptGraph: ConceptGraph

    // MARK: - Library

    public let progressOverview: ProgressOverviewResponse
    public let savedBookIds: [String]

    // MARK: - Computed convenience

    public var entitlementFreeValue: Entitlement { entitlementFree.entitlement }
    public var entitlementProValue: Entitlement { entitlementPro.entitlement }
    public var bookStateValue: BookUserBookState { bookState.state }
    public var dashboardValue: Dashboard { dashboard.dashboard }
    public var streakValue: StreakState { streak.streak }
    public var badgeItems: [BadgeItem] { badges.badges }
    public var notebookEntries: [NotebookEntry] { notebook.entries }
    public var reviewCards: [FsrsCard] { reviews.cards }
    public var notifications: [AppNotification] { notificationsResponse.notifications }

    // MARK: - Singleton

    /// The default shared instance backed by all fixture JSON files.
    public static let shared = PreviewDependencies()

    // MARK: - Init

    public init(
        books: [BookCatalogItem] = Fixtures.books,
        bookManifest: BookManifest = Fixtures.bookManifest,
        chapterEMH: ChapterResponse = Fixtures.chapterEMH,
        chapterPBC: ChapterResponse = Fixtures.chapterPBC,
        resolvedEMH: ResolvedChapter = Fixtures.resolvedEMH,
        resolvedPBC: ResolvedChapter = Fixtures.resolvedPBC,
        quizSession: QuizResponse = Fixtures.quizSession,
        quizResultPassed: QuizAttemptResult = Fixtures.quizResultPassed,
        quizResultFailed: QuizAttemptResult = Fixtures.quizResultFailed,
        entitlementFree: EntitlementResponse = Fixtures.entitlementFree,
        entitlementPro: EntitlementResponse = Fixtures.entitlementPro,
        bookState: BookStateResponse = Fixtures.bookState,
        dashboard: DashboardResponse = Fixtures.dashboard,
        streak: StreakResponse = Fixtures.streak,
        badges: BadgesResponse = Fixtures.badges,
        notebook: NotebookResponse = Fixtures.notebook,
        reviews: ReviewsResponse = Fixtures.reviews,
        notificationsResponse: NotificationsResponse = Fixtures.notificationsResponse,
        conceptGraph: ConceptGraph = Fixtures.conceptGraph,
        progressOverview: ProgressOverviewResponse = Fixtures.progressOverview,
        savedBookIds: [String] = Fixtures.savedBookIds
    ) {
        self.books = books
        self.bookManifest = bookManifest
        self.chapterEMH = chapterEMH
        self.chapterPBC = chapterPBC
        self.resolvedEMH = resolvedEMH
        self.resolvedPBC = resolvedPBC
        self.quizSession = quizSession
        self.quizResultPassed = quizResultPassed
        self.quizResultFailed = quizResultFailed
        self.entitlementFree = entitlementFree
        self.entitlementPro = entitlementPro
        self.bookState = bookState
        self.dashboard = dashboard
        self.streak = streak
        self.badges = badges
        self.notebook = notebook
        self.reviews = reviews
        self.notificationsResponse = notificationsResponse
        self.conceptGraph = conceptGraph
        self.progressOverview = progressOverview
        self.savedBookIds = savedBookIds
    }
}
