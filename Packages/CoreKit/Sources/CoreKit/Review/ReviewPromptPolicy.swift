import Foundation

/// The pure decision rule for whether to request an App Store review.
///
/// ``shouldRequestReview(for:currentVersion:lastPromptedVersion:)`` is a **pure function**
/// of its inputs — no I/O, no side effects, no singletons — so it is fully unit-testable.
/// Side effects (persisting the prompted version, actually invoking StoreKit) live in
/// ``ReviewPromptController``.
///
/// ### Guarantees
/// - Only fires at a genuine positive moment (see ``ReviewPromptMoment``); never after a
///   quiz failure, and there is no code path for an error to reach it.
/// - Requires real momentum for a quiz pass (a 3+ day reading streak).
/// - Never prompts twice for the same app version. StoreKit itself caps prompts to three
///   per 365 days and de-dupes per version; requiring a version change here is a stricter,
///   client-enforced floor so we don't even *ask* StoreKit more than once per release.
public enum ReviewPromptPolicy {

    /// The minimum consecutive-day reading streak before a quiz pass is "review-worthy".
    ///
    /// A passing quiz on its own is routine; a pass while the user is several days into a
    /// streak is a stronger signal that they're getting real value from the app.
    public static let minimumStreakForQuizPrompt = 3

    /// Decides whether the app should request an App Store review right now.
    ///
    /// - Parameters:
    ///   - moment: The positive moment that just occurred.
    ///   - currentVersion: The running app's short version (`CFBundleShortVersionString`).
    ///   - lastPromptedVersion: The version at which we last requested a review, or `nil`
    ///     if we've never prompted on this device.
    /// - Returns: `true` only when every gate passes.
    public static func shouldRequestReview(
        for moment: ReviewPromptMoment,
        currentVersion: String,
        lastPromptedVersion: String?
    ) -> Bool {
        // Defensive: with no resolvable version we can't honour the once-per-version cap,
        // so we decline rather than risk over-prompting.
        guard !currentVersion.isEmpty else { return false }

        // Never prompt more than once per app version.
        guard currentVersion != lastPromptedVersion else { return false }

        switch moment {
        case let .quizCompleted(passed, currentStreakDays):
            // Never after a failure, and only with genuine reading momentum.
            return passed && currentStreakDays >= minimumStreakForQuizPrompt
        case .bookFinished:
            return true
        }
    }
}
