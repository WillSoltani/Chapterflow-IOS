import Foundation
import Observation
import CoreKit

/// Coordinates the permission priming flow per docs/ios/PUSH-CONTRACT.md.
///
/// Rules:
/// - Never call `suggest(trigger:)` on first launch.
/// - The coordinator evaluates `hasPrimed` + OS status before showing the sheet.
/// - `hasPrimed` persists in `UserDefaults.standard` and must not be cleared
///   except during account-reset / sign-out flows.
@Observable
@MainActor
public final class NotificationPrimingCoordinator {

    // MARK: - Observable state

    /// Whether the priming sheet should be visible. Drive a `.sheet(isPresented:)`.
    public private(set) var isPrimingVisible: Bool = false

    // MARK: - Dependencies

    private let authorizer: any NotificationAuthorizerProtocol
    private let analytics: (any AnalyticsClient)?
    private let defaults: UserDefaults

    // MARK: - Persistence

    private static let hasPrimedKey = "com.chapterflow.notificationHasPrimed"

    /// Whether the user has already seen the priming sheet (or explicitly dismissed it).
    public private(set) var hasPrimed: Bool {
        get { defaults.bool(forKey: Self.hasPrimedKey) }
        set { defaults.set(newValue, forKey: Self.hasPrimedKey) }
    }

    // MARK: - Init

    public init(
        authorizer: any NotificationAuthorizerProtocol,
        analytics: (any AnalyticsClient)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.authorizer = authorizer
        self.analytics = analytics
        self.defaults = defaults
    }

    // MARK: - Suggest

    /// Suggests showing the priming sheet at a meaningful value moment.
    ///
    /// Shows the sheet only when:
    /// - `hasPrimed` is `false` (first time seeing the prompt), AND
    /// - The OS authorization status is `.notDetermined`.
    public func suggest(trigger: PrimingTrigger) async {
        let current = await authorizer.currentStatus()
        guard !hasPrimed, current == .notDetermined else { return }
        isPrimingVisible = true
        analytics?.track(.notificationPrimingShown)
    }

    // MARK: - Accept / Dismiss

    /// Called when the user taps "Enable" on the priming sheet.
    /// Marks `hasPrimed`, hides the sheet, then requests OS authorization.
    ///
    /// - Returns: The outcome of the OS authorization prompt.
    @discardableResult
    public func accept() async -> NotificationAuthorizationOutcome {
        hasPrimed = true
        isPrimingVisible = false
        analytics?.track(.notificationPrimingAccepted)
        return await authorizer.requestAuthorization()
    }

    /// Called when the user taps "Not Now" on the priming sheet.
    /// Marks `hasPrimed` and hides the sheet without requesting OS authorization.
    public func dismiss() {
        hasPrimed = true
        isPrimingVisible = false
        analytics?.track(.notificationPrimingDismissed)
    }
}

// MARK: - Trigger

/// The value-moment trigger that caused the priming sheet to appear.
/// Used for analytics; extend as new moments are identified.
public enum PrimingTrigger: String, Sendable {
    case firstChapterCompleted  = "first_chapter_completed"
    case chapterCompleted       = "chapter_completed"
    case streakMilestone        = "streak_milestone"
    case firstBookStarted       = "first_book_started"
    case reviewsDue             = "reviews_due"
    case readingReminderSet     = "reading_reminder_set"
}
