import Foundation

// MARK: - Onboarding endpoints

extension Endpoints {
    /// `GET /book/me/onboarding/progress` — fetch the user's saved onboarding state.
    /// Returns 404 when the user has no saved progress yet; the caller should treat
    /// `AppError.notFound` as "no progress exists" and start from the first step.
    public static func getOnboardingProgress() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/onboarding/progress")
    }

    /// `PATCH /book/me/onboarding/progress` — persist the current step and accumulated choices.
    public static func postOnboardingProgress(_ body: OnboardingProgressBody) throws -> Endpoint {
        try Endpoint(method: .patch, path: "/book/me/onboarding/progress", body: body)
    }

    /// `POST /book/me/onboarding/complete` — finalise onboarding with the user's full choices.
    public static func postOnboardingComplete(_ body: OnboardingCompleteBody) throws -> Endpoint {
        try Endpoint(method: .post, path: "/book/me/onboarding/complete", body: body)
    }
}

// MARK: - Request body types

/// Body for `PATCH /book/me/onboarding/progress`.
/// Partial fields are nullable so only accumulated choices are sent at each step.
public struct OnboardingProgressBody: Encodable, Sendable {
    public let step: String
    public let interests: [String]?
    /// Chapter-order preference: "summary_first" | "scenarios_first".
    public let chapterOrder: String?
    /// Teaching tone identifier matching the server's `VALID_TONES` list.
    public let tone: String?
    /// Daily reading goal in minutes. One of 10 | 20 | 30.
    public let dailyGoal: Int?
    public let reminderHour: Int?
    public let reminderMinute: Int?

    public init(
        step: String,
        interests: [String]? = nil,
        chapterOrder: String? = nil,
        tone: String? = nil,
        dailyGoal: Int? = nil,
        reminderHour: Int? = nil,
        reminderMinute: Int? = nil
    ) {
        self.step = step
        self.interests = interests
        self.chapterOrder = chapterOrder
        self.tone = tone
        self.dailyGoal = dailyGoal
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

/// Body for `POST /book/me/onboarding/complete`.
public struct OnboardingCompleteBody: Encodable, Sendable {
    public let interests: [String]
    /// Chapter-order preference: "summary_first" | "scenarios_first".
    public let chapterOrder: String
    /// Teaching tone identifier matching the server's `VALID_TONES` list.
    public let tone: String
    /// Daily reading goal in minutes. One of 10 | 20 | 30.
    public let dailyGoal: Int
    public let reminderHour: Int
    public let reminderMinute: Int

    public init(
        interests: [String],
        chapterOrder: String,
        tone: String,
        dailyGoal: Int,
        reminderHour: Int,
        reminderMinute: Int
    ) {
        self.interests = interests
        self.chapterOrder = chapterOrder
        self.tone = tone
        self.dailyGoal = dailyGoal
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}
