import Models

extension Fixtures {

    // MARK: - Progress overview

    /// Progress overview: Atomic Habits in-progress (ch.1 done of 5), Deep Work started (ch.1 of 5).
    public static let progressOverview: ProgressOverviewResponse = load("progress_overview")

    /// Convenience: the array of progress items.
    public static var progressItems: [ProgressOverviewItem] { progressOverview.progress }

    /// Progress for Atomic Habits (in-progress).
    public static var atomicHabitsProgress: ProgressOverviewItem { progressItems[0] }

    // MARK: - Saved books

    /// Saved book IDs: Deep Work and Thinking, Fast and Slow.
    public static let savedBooks: SavedBooksResponse = load("saved_books")

    /// Convenience: the saved book ID array.
    public static var savedBookIds: [String] { savedBooks.savedBookIds }
}
