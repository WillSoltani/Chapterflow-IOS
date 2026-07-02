import Models

extension Fixtures {

    // MARK: - Book state

    /// Book state for Atomic Habits: ch. 1 completed (score 100), ch. 2 unlocked.
    /// Includes `applicationStates`: ch.1 = applied, ch.2 = committed.
    public static let bookState: BookStateResponse = load("book_state")

    /// Convenience accessor.
    public static var bookStateValue: BookUserBookState { bookState.state }

    /// Application states keyed by chapterId.
    public static var applicationStates: [String: ChapterApplicationState]? { bookState.applicationStates }
}
