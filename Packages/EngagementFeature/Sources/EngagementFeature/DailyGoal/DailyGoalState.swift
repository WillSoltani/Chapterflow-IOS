import Foundation

// MARK: - DailyGoalDay

/// A single day's activity in the seven-day habit view.
public struct DailyGoalDay: Sendable {
    public let date: Date
    public let minutesRead: Int
    public let dailyGoal: Int

    // MARK: Derived

    /// Progress fraction (0–1) toward the daily goal for this day.
    public var fraction: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1.0, Double(minutesRead) / Double(dailyGoal))
    }

    public var isGoalMet: Bool { fraction >= 1.0 }
    public var hasActivity: Bool { minutesRead > 0 }

    public var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Single uppercase initial of the weekday (locale-aware).
    public var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EE"
        f.locale = Locale.current
        return String(f.string(from: date).prefix(1)).uppercased()
    }

    public var accessibilityLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let ds = fmt.string(from: date)
        guard hasActivity else { return "\(ds): no reading" }
        let goalStr = isGoalMet
            ? "goal met"
            : "\(dailyGoal - minutesRead) minute\(dailyGoal - minutesRead == 1 ? "" : "s") to go"
        return "\(ds): \(minutesRead) minute\(minutesRead == 1 ? "" : "s"), \(goalStr)"
    }
}

// MARK: - DailyGoalState

/// The computed state for the daily-goal surface.
///
/// Consumed by ``DailyGoalView`` and exposed publicly so widgets (P8.1) and
/// reminders (P9.3) can read `goalFraction` and `nudgeMessage` without
/// coupling to the full model.
public struct DailyGoalState: Sendable {
    public let goalMinutes: Int
    public let todayMinutes: Int
    /// Last 7 days ordered oldest → newest; index 6 is today.
    public let weekActivity: [DailyGoalDay]

    // MARK: Derived

    /// Progress fraction (0–1) toward the goal for today.
    public var goalFraction: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1.0, Double(todayMinutes) / Double(goalMinutes))
    }

    public var isGoalMet: Bool { goalFraction >= 1.0 }

    public var minutesRemaining: Int {
        max(0, goalMinutes - todayMinutes)
    }

    /// A calm, motivating one-line message. Never guilt-trippy.
    public var nudgeMessage: String {
        switch goalFraction {
        case 1.0...:
            return "Daily goal complete. Great reading today!"
        case 0.5...:
            return "Halfway there — \(minutesRemaining) more minute\(minutesRemaining == 1 ? "" : "s") to go."
        case 0.0001...:
            return "\(minutesRemaining) minute\(minutesRemaining == 1 ? "" : "s") to your \(goalMinutes)-minute goal."
        default:
            return "Open a chapter to start your reading habit for today."
        }
    }
}
