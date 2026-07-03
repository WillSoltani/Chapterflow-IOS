/// The reason a book or feature is inaccessible, returned by
/// ``EntitlementService/lockReason(for:isLockedByQuiz:)``.
///
/// Used to show the right paywall context and CTA at each gating point.
public enum LockReason: Sendable, Equatable {

    /// The user must subscribe to Pro to access this content.
    ///
    /// Applies when the user has no free starts remaining and never had any
    /// free book slots provisioned on their account — Pro is the only path.
    case needsPro

    /// The user has used all their free starts; they can earn more free slots
    /// via Flow Points, or subscribe to Pro.
    ///
    /// Applies when `freeBookSlots > 0` but `remainingFreeStarts == 0`.
    case needsFreeSlotOrPro

    /// The book is locked until the user passes a prerequisite quiz for the
    /// preceding book or chapter in a Journey or reading sequence.
    case lockedBehindQuiz
}
