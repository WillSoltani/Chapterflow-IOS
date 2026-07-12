import Foundation

/// A typed analytics event covering the app's key funnels.
///
/// Each case maps to a stable snake_case `name` sent to the backend, plus a set
/// of string `properties`. Keeping this an enum (rather than free-form strings)
/// means the funnel is defined in one place and is impossible to typo at a call
/// site. Use `.custom` sparingly for one-off events not worth a dedicated case.
public enum AnalyticsEvent: Sendable, Equatable {
    case appOpen
    /// A one-per-launch operational diagnostic emitted only after local build
    /// configuration validation succeeds. All associated values are explicitly
    /// allowlisted and contain no credentials, endpoints, or StoreKit IDs.
    case appConfigurationValidated(
        environment: AppEnvironment,
        bundleIdentifier: String,
        version: String,
        readiness: AppSubsystemReadiness
    )
    case signIn(method: String)
    case signOut
    case onboardingStep(index: Int)
    case bookStarted(bookId: String)
    case chapterOpened(bookId: String, chapter: Int)
    case chapterCompleted(bookId: String, chapter: Int)
    case quizStarted(bookId: String, chapter: Int)
    case quizSubmitted(bookId: String, chapter: Int, score: Int)
    case paywallViewed(source: String)
    case purchase(productId: String)
    case referralShared
    case notificationPrimingShown
    case notificationPrimingAccepted
    case notificationPrimingDismissed
    case notificationOSGranted
    case notificationOSDenied
    case notificationProvisionalGranted
    /// A local notification was successfully scheduled (i.e. added to UNUserNotificationCenter).
    case notificationSent(type: String)
    /// A server push notification was received by the device (foreground or background).
    case notificationReceived(type: String)
    /// The user tapped a notification or triggered an inline action on one.
    case notificationOpened(type: String, action: String)
    /// A spaced-repetition review session completed.
    case reviewCompleted(reviewed: Int)
    /// The user shared a card (streak, badge, chapter, or book) via the share sheet.
    case share(cardType: String)
    case custom(name: String, properties: [String: String])

    /// The stable wire name for this event.
    public var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .appConfigurationValidated: return "app_configuration_validated"
        case .signIn: return "sign_in"
        case .signOut: return "sign_out"
        case .onboardingStep: return "onboarding_step"
        case .bookStarted: return "book_started"
        case .chapterOpened: return "chapter_opened"
        case .chapterCompleted: return "chapter_completed"
        case .quizStarted: return "quiz_started"
        case .quizSubmitted: return "quiz_submitted"
        case .paywallViewed: return "paywall_viewed"
        case .purchase: return "purchase"
        case .referralShared: return "referral_shared"
        case .notificationPrimingShown: return "notification_priming_shown"
        case .notificationPrimingAccepted: return "notification_priming_accepted"
        case .notificationPrimingDismissed: return "notification_priming_dismissed"
        case .notificationOSGranted: return "notification_os_granted"
        case .notificationOSDenied: return "notification_os_denied"
        case .notificationProvisionalGranted: return "notification_provisional_granted"
        case .notificationSent:              return "notification_sent"
        case .notificationReceived:          return "notification_received"
        case .notificationOpened:            return "notification_opened"
        case .reviewCompleted:               return "review_completed"
        case .share:                         return "share"
        case .custom(let name, _): return name
        }
    }

    /// The event's properties, as a flat string dictionary suitable for JSON.
    public var properties: [String: String] {
        switch self {
        case .appOpen, .signOut, .referralShared,
             .notificationPrimingShown, .notificationPrimingAccepted, .notificationPrimingDismissed,
             .notificationOSGranted, .notificationOSDenied, .notificationProvisionalGranted:
            return [:]
        case let .appConfigurationValidated(
            environment,
            bundleIdentifier,
            version,
            readiness
        ):
            return [
                "environment": environment.rawValue,
                "bundleId": bundleIdentifier,
                "version": version,
                "networkingReady": String(readiness.networking),
                "authenticationReady": String(readiness.authentication),
                "storeKitReady": String(readiness.storeKit),
                "crashReportingReady": String(readiness.crashReporting),
                "appStoreDestinationReady": String(readiness.appStoreDestination)
            ]
        case .signIn(let method):
            return ["method": method]
        case .onboardingStep(let index):
            return ["index": String(index)]
        case .bookStarted(let bookId):
            return ["bookId": bookId]
        case .chapterOpened(let bookId, let chapter),
             .chapterCompleted(let bookId, let chapter),
             .quizStarted(let bookId, let chapter):
            return ["bookId": bookId, "chapter": String(chapter)]
        case .quizSubmitted(let bookId, let chapter, let score):
            return ["bookId": bookId, "chapter": String(chapter), "score": String(score)]
        case .paywallViewed(let source):
            return ["source": source]
        case .purchase(let productId):
            return ["productId": productId]
        case .notificationSent(let type):
            return ["type": type]
        case .notificationReceived(let type):
            return ["type": type]
        case .notificationOpened(let type, let action):
            return ["type": type, "action": action]
        case .reviewCompleted(let reviewed):
            return ["reviewed": String(reviewed)]
        case .share(let cardType):
            return ["cardType": cardType]
        case .custom(_, let properties):
            return properties
        }
    }
}
