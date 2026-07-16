import CoreKit
import Models

/// The primary call-to-action the book detail screen should present.
public enum BookDetailPrimaryAction: Equatable {
    /// The book hasn't been started; call `startBook` then navigate to chapter 1.
    case startReading
    /// The book is in progress; navigate directly to the current chapter.
    case continueReading
    /// The user has no access; open the paywall.
    case showPaywall
    /// The user is browsing as a guest; prompt sign-in before starting.
    case signInRequired
    /// Data is still loading; disable the button.
    case disabled
}

/// Why a chapter is currently inaccessible.
public enum ChapterLockReason: Equatable {
    /// The user must finish the prior chapter's quiz to unlock this one.
    case finishPriorQuiz
    /// The chapter requires a Pro subscription.
    case requiresPro
}

/// Server-authoritative private reading state for Book Detail.
public enum BookDetailPrivateState: Sendable {
    case loading
    case started(
        state: BookUserBookState,
        applicationStates: [String: ChapterApplicationState]
    )
    case notStarted
    case unavailable(UserFacingError)
    case compatibilityUnknown
}

/// Account entitlement state is tracked independently from public metadata and
/// book-state authority so one private request cannot erase a valid book outline.
public enum BookDetailEntitlementState: Sendable {
    case loading
    case available(Entitlement)
    case unavailable(UserFacingError)
    case notRequired
}
