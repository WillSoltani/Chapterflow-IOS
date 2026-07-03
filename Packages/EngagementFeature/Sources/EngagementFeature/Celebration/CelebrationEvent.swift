import Foundation
import Models

// MARK: - CelebrationEvent

/// A discrete moment that the CelebrationPresenter sequences and presents.
///
/// Every P5.x feature enqueues one or more of these after a server-side action
/// completes (e.g. a chapter quiz passes). The presenter is the single source of
/// truth and serialises them into one non-overlapping sequence.
public enum CelebrationEvent: Sendable {
    /// The chapter's entire quiz-pass loop completed.
    case loopComplete(chapterTitle: String)

    /// Flow-points were awarded by the server.
    case flowPointsGained(points: Int)

    /// The user's streak incremented by one day.
    case streakIncrement(newStreak: Int)

    /// The streak crossed a meaningful milestone (7, 14, 30, 60, 100, 365 …).
    case streakMilestone(streak: Int)

    /// The user's tier upgraded.
    case tierUp(newTier: String, previousTier: String?)

    /// A new badge was earned.
    case badgeEarned(badge: BadgeItem)

    /// A reflective "insight spark" prompt surfaced after completing a chapter.
    case insightSpark(prompt: String)

    /// All books in a multi-book journey were completed.
    case journeyComplete(title: String)
}

// MARK: - Equatable

// BadgeItem is Codable but not Equatable; compare by badgeId for the sequence guard.
extension CelebrationEvent: Equatable {
    public static func == (lhs: CelebrationEvent, rhs: CelebrationEvent) -> Bool {
        switch (lhs, rhs) {
        case (.loopComplete(let a), .loopComplete(let b)):
            return a == b
        case (.flowPointsGained(let a), .flowPointsGained(let b)):
            return a == b
        case (.streakIncrement(let a), .streakIncrement(let b)):
            return a == b
        case (.streakMilestone(let a), .streakMilestone(let b)):
            return a == b
        case (.tierUp(let a1, let a2), .tierUp(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.badgeEarned(let a), .badgeEarned(let b)):
            return a.badgeId == b.badgeId
        case (.insightSpark(let a), .insightSpark(let b)):
            return a == b
        case (.journeyComplete(let a), .journeyComplete(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - CelebrationEvent helpers

extension CelebrationEvent {
    /// The system-image name used for the event's icon in the celebration card.
    var systemImage: String {
        switch self {
        case .loopComplete:         return "checkmark.seal.fill"
        case .flowPointsGained:     return "bolt.fill"
        case .streakIncrement:      return "flame.fill"
        case .streakMilestone:      return "flame.fill"
        case .tierUp:               return "star.fill"
        case .badgeEarned:          return "medal.fill"
        case .insightSpark:         return "lightbulb.fill"
        case .journeyComplete:      return "trophy.fill"
        }
    }

    /// The headline displayed on the celebration card.
    var headline: String {
        switch self {
        case .loopComplete(let title):
            return "\u{201C}\(title)\u{201D} complete"
        case .flowPointsGained(let pts):
            return "+\(pts) Flow Points"
        case .streakIncrement(let n):
            return "\(n)-day streak"
        case .streakMilestone(let n):
            return "\(n)-day milestone"
        case .tierUp(let tier, _):
            return "Reached \(tier.capitalized)"
        case .badgeEarned(let b):
            return b.name
        case .insightSpark:
            return "Insight Spark"
        case .journeyComplete(let title):
            return "Journey Complete"
        }
    }

    /// A short supporting line beneath the headline.
    var subheadline: String? {
        switch self {
        case .loopComplete:
            return "All questions answered correctly."
        case .flowPointsGained:
            return "Keep learning to earn more."
        case .streakIncrement(let n):
            return "You've read \(n) days in a row."
        case .streakMilestone(let n):
            return "Incredible \u{2014} \(n) days straight!"
        case .tierUp(_, let prev):
            if let prev {
                return "You've gone beyond \(prev.capitalized)."
            }
            return "A new level of mastery unlocked."
        case .badgeEarned(let b):
            return b.description
        case .insightSpark(let p):
            return p
        case .journeyComplete(let title):
            return "You finished \u{201C}\(title)\u{201D}."
        }
    }

    /// Whether this event warrants confetti (off when Reduce Motion is enabled).
    var wantsConfetti: Bool {
        switch self {
        case .loopComplete, .tierUp, .streakMilestone, .badgeEarned, .journeyComplete:
            return true
        case .flowPointsGained, .streakIncrement, .insightSpark:
            return false
        }
    }

    /// How long (in seconds) the card stays on screen before auto-advancing.
    var autoAdvanceDuration: TimeInterval {
        switch self {
        case .loopComplete:     return 3.0
        case .flowPointsGained: return 2.0
        case .streakIncrement:  return 2.5
        case .streakMilestone:  return 3.0
        case .tierUp:           return 3.5
        case .badgeEarned:      return 3.0
        case .insightSpark:     return 5.0
        case .journeyComplete:  return 4.0
        }
    }
}
