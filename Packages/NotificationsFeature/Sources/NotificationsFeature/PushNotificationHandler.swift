import Foundation
import CoreKit

// MARK: - PushNotificationHandler (platform-independent routing logic)

/// Parses an incoming push notification userInfo payload and produces the
/// `chapterflow://` deep-link URL the app should navigate to.
///
/// **Payload contract (per docs/ios/PUSH-CONTRACT.md):**
/// The server SHOULD include a `"deepLink"` key with a `chapterflow://` URL.
/// When present it is used verbatim. When absent the handler synthesises a
/// sensible fallback from `"type"`, `"bookId"`, and `"chapterNumber"`.
///
/// **RF2:** An unrecognised `"type"` value falls through to a safe default
/// (`chapterflow://engagement`) and never crashes.
///
/// **Routing table (per PUSH-CONTRACT.md):**
/// | type                 | default deep-link               |
/// |----------------------|---------------------------------|
/// | badge_earned         | chapterflow://engagement        |
/// | tier_up              | chapterflow://engagement        |
/// | streak_milestone     | chapterflow://engagement        |
/// | insight_spark        | chapterflow://book/{id}/ch/{n} or engagement |
/// | reading_reminder     | chapterflow://book/{id}/ch/{n} or library    |
/// | streak_at_risk       | chapterflow://review            |
/// | partner_nudge        | chapterflow://profile           |
/// | commitment_followup  | chapterflow://book/{id}/ch/{n} or library    |
/// | event_reminder       | chapterflow://engagement        |
/// | scenario_approved    | chapterflow://engagement        |
/// | scenario_rejected    | chapterflow://engagement        |
/// | unknown              | chapterflow://engagement        |
public enum PushNotificationHandler {

    // MARK: - Public API

    /// Extracts the routing URL from raw `userInfo` and an action identifier.
    ///
    /// This overload is platform-independent and can be called from unit tests
    /// on macOS as well as from the UIKit `UNUserNotificationCenterDelegate`.
    ///
    /// Never returns `nil` — every push type maps to at least the engagement
    /// home as a safe fallback.
    public static func routingURL(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String
    ) -> URL {
        // 1. Prefer an explicit deep link embedded in the payload.
        if let urlString = userInfo["deepLink"] as? String,
           let url = URL(string: urlString),
           url.scheme?.lowercased() == "chapterflow" {
            return url
        }

        // 2. Parse payload fields.
        let typeRaw = userInfo["type"] as? String ?? ""
        let pushType = PushNotificationType(rawValue: typeRaw)
        let bookId = userInfo["bookId"] as? String
        let chapterNumber = userInfo["chapterNumber"] as? Int
            ?? (userInfo["chapterNumber"] as? String).flatMap(Int.init)

        // 3. Action-button overrides (inline notification actions).
        if let actionURL = urlForAction(actionIdentifier, bookId: bookId, chapter: chapterNumber) {
            return actionURL
        }

        // 4. Default per-type routing (RF2: unknown → engagement, never crashes).
        return urlForType(pushType, bookId: bookId, chapter: chapterNumber)
    }

    // MARK: - Private helpers

    private static func urlForAction(_ action: String, bookId: String?, chapter: Int?) -> URL? {
        switch action {
        case PushActionIdentifier.reviewNow:
            return deepLinkURL("review")
        case PushActionIdentifier.openChapter:
            return chapterOrFallback(bookId: bookId, chapter: chapter, fallback: "library")
        default:
            return nil
        }
    }

    private static func urlForType(_ type: PushNotificationType, bookId: String?, chapter: Int?) -> URL {
        switch type {
        case .badgeEarned, .tierUp, .streakMilestone, .eventReminder,
             .scenarioApproved, .scenarioRejected, .unknown:
            return deepLinkURL("engagement")
        case .insightSpark:
            return chapterOrFallback(bookId: bookId, chapter: chapter, fallback: "engagement")
        case .readingReminder, .commitmentFollowup:
            return chapterOrFallback(bookId: bookId, chapter: chapter, fallback: "library")
        case .streakAtRisk:
            return deepLinkURL("review")
        case .partnerNudge:
            return deepLinkURL("profile")
        }
    }

    private static func chapterOrFallback(bookId: String?, chapter: Int?, fallback: String) -> URL {
        if let bid = bookId, let num = chapter {
            return deepLinkURL("book/\(bid)/chapter/\(num)")
        }
        return deepLinkURL(fallback)
    }

    private static func deepLinkURL(_ path: String) -> URL {
        // Force-unwrap is safe: we own the scheme and only pass valid path strings.
        URL(string: "chapterflow://\(path)")!
    }
}

// MARK: - UIKit-only extensions

#if canImport(UIKit)
import UserNotifications

public extension PushNotificationHandler {
    /// Extracts the routing URL from a `UNNotificationResponse` (a tap or action press).
    static func routingURL(for response: UNNotificationResponse) -> URL {
        routingURL(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        )
    }
}

// MARK: - Push routing bridge

/// A thread-safe bridge between the UIKit app-delegate notification tap callback
/// and the @Observable `AppModel` that owns navigation.
///
/// Pattern mirrors `APNSRegistrationBridge`: the bridge is a shared singleton that
/// the `AppDelegate` calls into; `AppModel` / `AppRootView` sets the closure.
public final class PushRoutingBridge: @unchecked Sendable {
    public static let shared = PushRoutingBridge()

    /// Called on the main actor whenever the user taps a push notification or
    /// an inline notification action. Set this from `AppModel` / `AppRootView`.
    @MainActor
    public var onNotificationTapped: ((URL) -> Void)?

    private init() {}

    /// Invoke from `AppDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    /// Nonisolated so UIKit delegate callbacks can call it freely; dispatches to
    /// the main actor internally before invoking `onNotificationTapped`.
    public nonisolated func didReceiveResponse(_ response: UNNotificationResponse) {
        let url = PushNotificationHandler.routingURL(for: response)
        Task { @MainActor [self] in
            self.onNotificationTapped?(url)
        }
    }
}
#endif
