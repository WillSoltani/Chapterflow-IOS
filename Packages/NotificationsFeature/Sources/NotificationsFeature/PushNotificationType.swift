import Foundation

/// The server-defined push notification type, carried in the payload's `"type"` key.
///
/// **RF2 tolerant decoding:** unknown raw values decode to `.unknown(rawValue)` instead
/// of crashing. Every `switch` must explicitly handle `.unknown` — never use
/// `@unknown default` as it hides newly-added server cases from the compiler.
public enum PushNotificationType: Sendable, Equatable {
    case badgeEarned
    case tierUp
    case streakMilestone
    case insightSpark
    case readingReminder
    case streakAtRisk
    case partnerNudge
    case commitmentFollowup
    case eventReminder
    case scenarioApproved
    case scenarioRejected
    /// Local-only type for FSRS review-due notifications (not sent by the server).
    case reviewDue
    /// A push type the client does not yet recognise. Route to a safe default; never crash.
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .badgeEarned:          return "badge_earned"
        case .tierUp:               return "tier_up"
        case .streakMilestone:      return "streak_milestone"
        case .insightSpark:         return "insight_spark"
        case .readingReminder:      return "reading_reminder"
        case .streakAtRisk:         return "streak_at_risk"
        case .partnerNudge:         return "partner_nudge"
        case .commitmentFollowup:   return "commitment_followup"
        case .eventReminder:        return "event_reminder"
        case .scenarioApproved:     return "scenario_approved"
        case .scenarioRejected:     return "scenario_rejected"
        case .reviewDue:            return "review_due"
        case .unknown(let s):       return s
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "badge_earned":          self = .badgeEarned
        case "tier_up":               self = .tierUp
        case "streak_milestone":      self = .streakMilestone
        case "insight_spark":         self = .insightSpark
        case "reading_reminder":      self = .readingReminder
        case "streak_at_risk":        self = .streakAtRisk
        case "partner_nudge":         self = .partnerNudge
        case "commitment_followup":   self = .commitmentFollowup
        case "event_reminder":        self = .eventReminder
        case "scenario_approved":     self = .scenarioApproved
        case "scenario_rejected":     self = .scenarioRejected
        case "review_due":            self = .reviewDue
        default:                      self = .unknown(rawValue)
        }
    }

    /// UNNotificationCategory identifier for this push type.
    /// Used when registering categories and when the server sets `"category"` in the aps payload.
    public var categoryIdentifier: String {
        switch self {
        case .badgeEarned:          return "CF_BADGE_EARNED"
        case .tierUp:               return "CF_TIER_UP"
        case .streakMilestone:      return "CF_STREAK_MILESTONE"
        case .insightSpark:         return "CF_INSIGHT_SPARK"
        case .readingReminder:      return "CF_READING_REMINDER"
        case .streakAtRisk:         return "CF_STREAK_AT_RISK"
        case .partnerNudge:         return "CF_PARTNER_NUDGE"
        case .commitmentFollowup:   return "CF_COMMITMENT_FOLLOWUP"
        case .eventReminder:        return "CF_EVENT_REMINDER"
        case .scenarioApproved:     return "CF_SCENARIO_APPROVED"
        case .scenarioRejected:     return "CF_SCENARIO_REJECTED"
        case .reviewDue:            return "CF_REVIEW_DUE"
        case .unknown:              return "CF_GENERAL"
        }
    }

    /// All known (non-unknown) push types; used to register UNNotificationCategory objects.
    public static let known: [PushNotificationType] = [
        .badgeEarned, .tierUp, .streakMilestone, .insightSpark,
        .readingReminder, .streakAtRisk, .partnerNudge, .commitmentFollowup,
        .eventReminder, .scenarioApproved, .scenarioRejected, .reviewDue
    ]
}

// MARK: - Notification action identifiers (payload `"category"` field)

public enum PushActionIdentifier {
    /// Foreground action: opens the app to the relevant chapter/book.
    public static let openChapter   = "CF_ACTION_OPEN_CHAPTER"
    /// Foreground action: opens the Reviews tab immediately.
    public static let reviewNow     = "CF_ACTION_REVIEW_NOW"
    /// Foreground action: opens the engagement/badge screen.
    public static let viewBadge     = "CF_ACTION_VIEW_BADGE"
    /// Foreground action: opens the engagement dashboard.
    public static let viewProgress  = "CF_ACTION_VIEW_PROGRESS"
    /// Background action: reschedules the reminder; no app open required.
    public static let snooze        = "CF_ACTION_SNOOZE"
}
