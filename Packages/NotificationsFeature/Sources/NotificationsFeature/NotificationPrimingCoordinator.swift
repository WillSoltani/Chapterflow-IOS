import Foundation
import Observation
import CoreKit

/// The high-value moment that triggered a priming suggestion.
public enum NotificationPrimingTrigger: Sendable {
    /// User finished their first chapter — highest-value reading moment.
    case firstChapterCompleted
    /// User navigated to set a reading reminder — explicit intent.
    case readingReminderSet

    var analyticsValue: String {
        switch self {
        case .firstChapterCompleted: return "first_chapter_completed"
        case .readingReminderSet: return "reading_reminder_set"
        }
    }
}

/// State machine that decides when to show the notification priming screen.
///
/// **Rules enforced here (never elsewhere):**
/// - Only surfaces priming when the OS status is `.notDetermined`.
/// - Only surfaces priming once per install ("hasPrimed" gate in UserDefaults).
/// - A high-value moment must be signalled via `suggest(trigger:)`.
///
/// **Usage pattern:**
/// ```swift
/// // After user completes their first chapter:
/// await coordinator.suggest(trigger: .firstChapterCompleted)
///
/// // In the view:
/// .sheet(isPresented: Binding(
///     get: { coordinator.isPrimingVisible },
///     set: { if !$0 { coordinator.dismiss() } }
/// )) {
///     NotificationPrimingView(
///         onAccept: { await coordinator.accept() },
///         onDismiss: { coordinator.dismiss() }
///     )
/// }
/// ```
@MainActor
@Observable
public final class NotificationPrimingCoordinator {

    // MARK: - Observable state

    /// `true` while the priming sheet should be presented.
    public private(set) var isPrimingVisible: Bool = false

    // MARK: - Dependencies

    private let authorizer: any NotificationAuthorizerProtocol
    private let analytics: any AnalyticsClient
    private let defaults: UserDefaults

    // MARK: - Persistence keys

    private enum Keys {
        static let hasPrimed = "com.chapterflow.notifications.hasPrimed"
    }

    // MARK: - Init

    public init(
        authorizer: any NotificationAuthorizerProtocol,
        analytics: any AnalyticsClient,
        defaults: UserDefaults = .standard
    ) {
        self.authorizer = authorizer
        self.analytics = analytics
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Signal that a high-value moment occurred.
    ///
    /// The coordinator evaluates whether to surface the priming sheet.
    /// No-ops if the user has already been primed or the OS status is not
    /// `.notDetermined` (i.e., already granted or already denied).
    public func suggest(trigger: NotificationPrimingTrigger) async {
        guard !hasPrimed else { return }
        let status = await authorizer.currentStatus()
        guard status == .notDetermined else { return }
        isPrimingVisible = true
        analytics.track(.custom(
            name: "notification_priming_shown",
            properties: ["trigger": trigger.analyticsValue]
        ))
    }

    /// User accepted the priming explanation — fires the OS authorization prompt.
    ///
    /// - Returns: The outcome of the OS prompt (.granted / .denied).
    @discardableResult
    public func accept() async -> NotificationAuthorizationOutcome {
        markPrimed()
        isPrimingVisible = false
        analytics.track(.custom(name: "notification_priming_accepted", properties: [:]))
        return await authorizer.requestAuthorization()
    }

    /// User dismissed the priming sheet without accepting ("Not Now").
    public func dismiss() {
        markPrimed()
        isPrimingVisible = false
        analytics.track(.custom(name: "notification_priming_dismissed", properties: [:]))
    }

    // MARK: - Private

    private var hasPrimed: Bool {
        defaults.bool(forKey: Keys.hasPrimed)
    }

    private func markPrimed() {
        defaults.set(true, forKey: Keys.hasPrimed)
    }
}
