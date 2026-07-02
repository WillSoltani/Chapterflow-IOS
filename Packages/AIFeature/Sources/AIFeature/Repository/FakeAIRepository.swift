import CoreKit

/// In-memory ``AIRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with a canned response or a forced error to drive any test scenario.
public actor FakeAIRepository: AIRepository {

    private let response: BookAskResponse?
    private let forcedError: AppError?
    /// Artificial delay in seconds to simulate network latency in previews.
    private let delay: Double

    public init(
        response: BookAskResponse? = FakeAIRepository.sampleResponse,
        error: AppError? = nil,
        delay: Double = 0.0
    ) {
        self.response = response
        self.forcedError = error
        self.delay = delay
    }

    public func askBook(
        bookId: String,
        question: String,
        selectionContext: String?,
        tone: String?
    ) async throws -> BookAskResponse {
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        if let error = forcedError { throw error }
        guard let response else {
            throw AppError.server(code: "no_response", message: "No fake response configured.", requestId: nil)
        }
        return response
    }

    // MARK: - Sample data

    public static let sampleResponse = BookAskResponse(
        answer: """
        Atomic habits work through the **compound effect** of small, consistent changes. \
        Rather than aiming for dramatic transformations, the system focuses on improving \
        by just *1% each day*.

        Key mechanisms include:
        - **Cue → Craving → Response → Reward** loops that wire new behaviours into the brain
        - Identity-based change: becoming the type of person who does the habit
        - `Environment design` that makes the desired behaviour easier

        The author argues that outcomes are a lagging measure of habits — you don't \
        *rise* to your goals, you *fall* to the level of your systems.
        """,
        citations: [1, 2, 4],
        remainingQuestions: 4
    )

    public static let rateLimitedError = AppError.rateLimited(retryAfter: nil)
    public static let offlineError = AppError.offline
}
