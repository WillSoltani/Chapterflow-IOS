import AppIntents

// MARK: - LogDailyReadingIntent

/// Legacy intent retained so previously donated shortcuts fail closed.
/// New shortcut donations omit it until reading minutes can carry account
/// ownership across the extension boundary in WP-ID-01B.
public struct LogDailyReadingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reading time logging unavailable"
    public static let description = IntentDescription(
        "Reading time logging from Siri is temporarily unavailable.",
        categoryName: "Reading"
    )
    /// Keep cached invocations inline and explicit; do not emit ownerless data.
    public static let openAppWhenRun = false

    @Parameter(title: "Minutes read", description: "How many minutes did you read?", default: 20)
    public var minutesRead: Int

    public init() {}

    public func perform() async throws -> some IntentResult {
        return .result(
            dialog: "Reading time can’t be logged from Siri yet."
        )
    }
}
