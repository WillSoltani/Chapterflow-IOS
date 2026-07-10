import Foundation
import os

/// Coordinates App Store review requests: applies ``ReviewPromptPolicy`` and, when it
/// passes, invokes the caller-supplied request action and records the prompted version.
///
/// The controller is intentionally UI- and StoreKit-agnostic: the actual review request
/// is passed in as a closure (typically wrapping SwiftUI's `RequestReviewAction` from the
/// `\.requestReview` environment value). This keeps CoreKit free of a StoreKit dependency
/// and makes the whole thing unit-testable with a spy closure.
///
/// ```swift
/// // At the call site (a SwiftUI view with @Environment(\.requestReview)):
/// controller.requestReviewIfAppropriate(
///     for: .quizCompleted(passed: true, currentStreakDays: streak)
/// ) {
///     Task { await requestReview() }
/// }
/// ```
@MainActor
public final class ReviewPromptController {

    private let store: any ReviewPromptVersionStore
    private let currentVersion: String
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "ReviewPrompt")

    /// - Parameters:
    ///   - store: Where the last-prompted version is persisted.
    ///   - currentVersion: The running app's short version (`CFBundleShortVersionString`).
    public init(store: any ReviewPromptVersionStore, currentVersion: String) {
        self.store = store
        self.currentVersion = currentVersion
    }

    /// Requests a review if — and only if — ``ReviewPromptPolicy`` allows it for `moment`.
    ///
    /// When the policy passes, `performRequest` is invoked and the current version is
    /// recorded so we never prompt again on this version.
    ///
    /// - Parameters:
    ///   - moment: The positive moment that just occurred.
    ///   - performRequest: The action that actually asks StoreKit for a review.
    /// - Returns: `true` if a review was requested, `false` if the policy declined.
    @discardableResult
    public func requestReviewIfAppropriate(
        for moment: ReviewPromptMoment,
        performRequest: () -> Void
    ) -> Bool {
        guard ReviewPromptPolicy.shouldRequestReview(
            for: moment,
            currentVersion: currentVersion,
            lastPromptedVersion: store.lastPromptedVersion()
        ) else {
            return false
        }

        performRequest()
        store.setLastPromptedVersion(currentVersion)
        logger.info("Requested App Store review for version \(self.currentVersion, privacy: .public)")
        return true
    }
}
