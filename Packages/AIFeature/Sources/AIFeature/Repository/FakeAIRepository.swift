import CoreKit
import Models

/// In-memory ``AIRepository`` for unit tests and SwiftUI previews.
///
/// Seed it with a canned response or a forced error to drive any test scenario.
public actor FakeAIRepository: AIRepository {

    private let response: BookAskResponse?
    private let graphResponse: ConceptGraph?
    private let depthResponse: DepthRecommendation?
    private let forcedError: AppError?
    /// Artificial delay in seconds to simulate network latency in previews.
    private let delay: Double

    public init(
        response: BookAskResponse? = FakeAIRepository.sampleResponse,
        graph: ConceptGraph? = FakeAIRepository.sampleConceptGraph,
        depth: DepthRecommendation? = FakeAIRepository.sampleDepthRecommendation,
        error: AppError? = nil,
        delay: Double = 0.0
    ) {
        self.response = response
        self.graphResponse = graph
        self.depthResponse = depth
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

    public func conceptGraph(bookId: String) async throws -> ConceptGraph {
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        if let error = forcedError { throw error }
        guard let graph = graphResponse else {
            throw AppError.server(code: "no_graph", message: "No fake graph configured.", requestId: nil)
        }
        return graph
    }

    public func depthRecommendation(bookId: String) async throws -> DepthRecommendation {
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        if let error = forcedError { throw error }
        guard let depth = depthResponse else {
            throw AppError.server(code: "no_depth", message: "No fake depth recommendation configured.", requestId: nil)
        }
        return depth
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

    public static let sampleConceptGraph = ConceptGraph(
        concepts: [
            ConceptNode(id: "habit-loop", label: "Habit Loop", introducedIn: "1", summary: "The neurological feedback loop — cue, craving, response, reward — that drives all habitual behaviour."),
            ConceptNode(id: "identity-change", label: "Identity-Based Change", introducedIn: "2", summary: "Shifting your self-image to match your desired habits. 'I am a runner' vs 'I am trying to run'."),
            ConceptNode(id: "cue", label: "Cue", introducedIn: "1", summary: "The trigger that initiates a habit. Can be a time, place, emotion, other people, or a preceding action."),
            ConceptNode(id: "craving", label: "Craving", introducedIn: "1", summary: "The motivational force behind every habit. You don't crave the habit itself but the change in state it delivers."),
            ConceptNode(id: "environment-design", label: "Environment Design", introducedIn: "3", summary: "Structuring your physical and social environment to make desired behaviours obvious and undesired ones invisible."),
            ConceptNode(id: "two-minute-rule", label: "Two-Minute Rule", introducedIn: "4", summary: "Scale down any habit to a two-minute version to make starting easy."),
            ConceptNode(id: "reward", label: "Reward", introducedIn: "1", summary: "The end goal of every habit. Rewards close the feedback loop and teach the brain which actions are worth repeating."),
            ConceptNode(id: "compound-growth", label: "Compound Growth", introducedIn: "1", summary: "1% better every day yields 37× improvement after a year. Small consistent gains compound into extraordinary results."),
            ConceptNode(id: "habit-stacking", label: "Habit Stacking", introducedIn: "3", summary: "Pairing a new habit with an existing one using 'After I [current habit], I will [new habit]'."),
        ],
        edges: [
            ConceptEdge(from: "cue", to: "habit-loop", edgeType: .prerequisite),
            ConceptEdge(from: "craving", to: "habit-loop", edgeType: .prerequisite),
            ConceptEdge(from: "reward", to: "habit-loop", edgeType: .prerequisite),
            ConceptEdge(from: "habit-loop", to: "identity-change", edgeType: .prerequisite),
            ConceptEdge(from: "habit-loop", to: "environment-design", edgeType: .prerequisite),
            ConceptEdge(from: "environment-design", to: "habit-stacking", edgeType: .prerequisite),
            ConceptEdge(from: "habit-loop", to: "two-minute-rule", edgeType: .prerequisite),
            ConceptEdge(from: "compound-growth", to: "identity-change", edgeType: .prerequisite),
        ],
        chapterIntroduces: [
            "1": ["habit-loop", "cue", "craving", "reward", "compound-growth"],
            "2": ["identity-change"],
            "3": ["environment-design", "habit-stacking"],
            "4": ["two-minute-rule"],
        ],
        chapterRequires: [
            "2": ["habit-loop"],
            "3": ["habit-loop"],
            "4": ["habit-loop", "environment-design"],
        ]
    )

    /// A confident recommendation (medium/balanced) for use in previews and tests.
    public static let sampleDepthRecommendation = DepthRecommendation(
        recommendedDepth: .medium,
        confidence: 0.85
    )

    /// A low-confidence recommendation — should be hidden by the UI.
    public static let lowConfidenceDepthRecommendation = DepthRecommendation(
        recommendedDepth: .hard,
        confidence: 0.4
    )

    public static let rateLimitedError = AppError.rateLimited(retryAfter: nil)
    public static let offlineError = AppError.offline
}
