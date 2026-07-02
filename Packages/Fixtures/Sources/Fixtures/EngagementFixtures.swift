import Models

extension Fixtures {

    // MARK: - Dashboard

    /// Progress dashboard: 5-day streak, analyst tier, 4 due reviews, continue Atomic Habits.
    public static let dashboard: DashboardResponse = load("dashboard")

    /// Convenience accessor.
    public static var dashboardValue: Dashboard { dashboard.dashboard }

    // MARK: - Streak

    /// Streak state: 5-day current streak, 12-day best, 1 shield held, 5-day history.
    public static let streak: StreakResponse = load("streak")

    /// Convenience accessor.
    public static var streakValue: StreakState { streak.streak }

    // MARK: - Badges

    /// Badge collection: 2 earned (First Chapter, Bookworm) + 2 locked (Week Warrior, Explorer).
    public static let badges: BadgesResponse = load("badges")

    /// Convenience accessor.
    public static var badgeItems: [BadgeItem] { badges.badges }

    /// Earned badges only.
    public static var earnedBadges: [BadgeItem] { badgeItems.filter(\.isEarned) }

    /// Locked (unearned) badges.
    public static var lockedBadges: [BadgeItem] { badgeItems.filter { !$0.isEarned } }

    // MARK: - Notebook

    /// Notebook entries: 2 for Atomic Habits (note + highlight + commitment), 1 Deep Work, 1 bookmark.
    public static let notebook: NotebookResponse = load("notebook")

    /// Convenience accessor.
    public static var notebookEntries: [NotebookEntry] { notebook.entries }

    // MARK: - Reviews (FSRS cards)

    /// FSRS review deck: 2 due cards (Atomic Habits), 1 new card (Deep Work).
    public static let reviews: ReviewsResponse = load("reviews")

    /// Convenience accessor.
    public static var reviewCards: [FsrsCard] { reviews.cards }

    /// Due cards only.
    public static var dueCards: [FsrsCard] { reviewCards.filter { $0.state == .due } }
}
