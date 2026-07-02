/// Pure, stateless business logic for evaluating a user's subscription entitlement.
///
/// All methods are side-effect-free `Sendable` value semantics — safe to call from
/// any concurrency context.
public struct EntitlementEvaluator: Sendable {
    public init() {}

    // MARK: - Pro status

    /// `true` if the user holds an active Pro subscription.
    public func isPro(_ entitlement: Entitlement) -> Bool {
        entitlement.plan == .pro && entitlement.proStatus == "active"
    }

    // MARK: - Book access

    /// `true` if the user can start (or continue) the given book.
    ///
    /// Access is granted when ANY of the following is true:
    /// - The user is Pro (active).
    /// - The book is in the user's unlocked-book list.
    /// - The user has remaining free-start slots.
    public func canStart(bookId: String, entitlement: Entitlement) -> Bool {
        if isPro(entitlement) { return true }
        if entitlement.unlockedBookIds.contains(bookId) { return true }
        return entitlement.remainingFreeStarts > 0
    }

    // MARK: - Chapter access

    /// `true` if the chapter at `number` is within the unlocked range for this book.
    ///
    /// The server is the authority on unlock state; this mirrors the server's
    /// `unlockedThroughChapterNumber` boundary.
    public func isChapterUnlocked(number: Int, progress: BookProgress) -> Bool {
        number <= progress.unlockedThroughChapterNumber
    }

    /// `true` if the chapter ID appears in the state's unlocked-chapter list.
    public func isChapterUnlocked(chapterId: String, state: BookUserBookState) -> Bool {
        state.unlockedChapterIds.contains(chapterId)
    }
}
