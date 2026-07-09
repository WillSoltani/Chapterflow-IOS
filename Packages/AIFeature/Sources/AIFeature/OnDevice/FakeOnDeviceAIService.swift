import Foundation

/// Deterministic ``OnDeviceAIProviding`` for unit tests and SwiftUI previews.
///
/// Configure via the ``availability`` parameter and optional ``delay`` to
/// simulate latency. Useful for driving available / unavailable previews.
public actor FakeOnDeviceAIService: OnDeviceAIProviding {

    // MARK: - Configuration

    private let _availability: OnDeviceAIAvailability
    private let delay: Double
    private let forcedError: (any Error)?

    public init(
        availability: OnDeviceAIAvailability = .available,
        delay: Double = 0.0,
        forcedError: (any Error)? = nil
    ) {
        self._availability = availability
        self.delay = delay
        self.forcedError = forcedError
    }

    // MARK: - OnDeviceAIProviding

    public var availability: OnDeviceAIAvailability { _availability }

    public func summarizeChapter(title: String, text: String) async throws -> String {
        try await simulateWork()
        return """
        This chapter explores the core principles behind \(title). \
        The central insight is that small, consistent changes compound into extraordinary results over time. \
        By understanding the underlying mechanisms, readers can design better systems for lasting change.
        """
    }

    public func explainHighlight(_ highlight: String, chapterText: String) async throws -> String {
        try await simulateWork()
        return """
        This passage means that the results we see are the product of systems running in the background, \
        not single grand actions. In simpler terms: the process matters more than the outcome.
        """
    }

    public func answerQuestion(
        _ question: String,
        chapterText: String,
        selectionContext: String?
    ) async throws -> String {
        try await simulateWork()
        return """
        Based on the downloaded chapter, the answer relates to the compounding nature of small habits. \
        The text explains that 1% improvements each day lead to a 37× gain over a year — \
        a powerful argument for consistency over intensity.
        """
    }

    public func suggestHighlights(from text: String, count: Int = 3) async throws -> [String] {
        try await simulateWork()
        return [
            "Habits are the compound interest of self-improvement.",
            "You do not rise to the level of your goals; you fall to the level of your systems.",
            "Every action is a vote for the type of person you wish to become.",
        ].prefix(count).map { String($0) }
    }

    // MARK: - Helpers

    private func simulateWork() async throws {
        if let error = forcedError { throw error }
        guard _availability.isAvailable else {
            throw OnDeviceAIError.unavailable(_availability)
        }
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
    }
}
