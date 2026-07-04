import Foundation

// MARK: - Onboarding step

/// The ordered steps in the first-run onboarding flow.
public enum OnboardingStep: String, Sendable, Equatable, CaseIterable {
    case welcome
    case interests
    case readingPrefs
    case dailyGoal
    case notifications
    case completed
}

// MARK: - ChapterOrder

/// The user's preferred chapter-reading order.
///
/// Raw values match the server's `chapterOrder` field: "summary_first" | "scenarios_first".
public enum ChapterOrder: String, Sendable, CaseIterable {
    case summaryFirst = "summary_first"
    case scenariosFirst = "scenarios_first"
}

// MARK: - Server response types

/// Outer wrapper returned by `GET /book/me/onboarding/progress`.
struct OnboardingGetProgressResponse: Decodable, Sendable {
    let progress: OnboardingServerProgress?
}

/// The user's persisted onboarding state from the server.
public struct OnboardingServerProgress: Decodable, Sendable {
    public let step: String
    public let completed: Bool
    public let interests: [String]?
    /// Chapter-order preference: "summary_first" | "scenarios_first".
    public let chapterOrder: String?
    /// Teaching tone identifier.
    public let tone: String?
    /// Daily reading goal in minutes. One of 10 | 20 | 30.
    public let dailyGoal: Int?
    public let reminderHour: Int?
    public let reminderMinute: Int?
}

/// Acknowledgment response from POST progress and POST complete endpoints.
/// The server may return additional fields; we only need to confirm decode success.
struct OnboardingAckResponse: Decodable, Sendable {
    // Tolerant: unknown fields are ignored by Swift Codable synthesis.
}
