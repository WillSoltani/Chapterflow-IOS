import AppIntents
import Persistence

// MARK: - LogDailyReadingIntent

/// Interactive intent: "Log today's reading" — records offline reading time.
///
/// Runs fully inline (no app launch). Accumulates the reported minutes in
/// App Group UserDefaults under ``IntentKeys/pendingReadingMinutes``; the main
/// app credits them toward today's goal ring on next activation.
public struct LogDailyReadingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log today's reading"
    public static let description = IntentDescription(
        "Records how many minutes you've read today.",
        categoryName: "Reading"
    )
    /// Runs inline — Siri asks for the parameter and confirms without opening the app.
    public static let openAppWhenRun = false

    @Parameter(title: "Minutes read", description: "How many minutes did you read?", default: 20)
    public var minutesRead: Int

    public init() {}

    public func perform() async throws -> some IntentResult {
        let minutes = max(1, minutesRead)
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let existing = defaults?.integer(forKey: IntentKeys.pendingReadingMinutes) ?? 0
        defaults?.set(existing + minutes, forKey: IntentKeys.pendingReadingMinutes)
        let noun = minutes == 1 ? "minute" : "minutes"
        return .result(dialog: "Got it! I've noted \(minutes) \(noun) of reading for today.")
    }
}
