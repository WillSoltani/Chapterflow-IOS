import Foundation

// MARK: - Protocol

/// The data contract for on-device AI generation.
///
/// Two conformances ship:
/// - ``OnDeviceAIService`` — uses `SystemLanguageModel` on iOS 26+ / macOS 26+
///   with Apple Intelligence; gated by `#if canImport(FoundationModels)`.
/// - ``FakeOnDeviceAIService`` — deterministic fake for tests and previews.
///
/// All methods throw ``OnDeviceAIError`` on failure; callers must handle the
/// `.unavailable` case to degrade silently.
public protocol OnDeviceAIProviding: Sendable {
    /// Current availability of the on-device model.
    var availability: OnDeviceAIAvailability { get async }
    /// Generates a chapter summary grounded in the supplied text.
    func summarizeChapter(title: String, text: String) async throws -> String
    /// Explains a highlighted passage in simple terms, grounded in the chapter text.
    func explainHighlight(_ highlight: String, chapterText: String) async throws -> String
    /// Answers a question offline, grounded in the downloaded chapter text.
    func answerQuestion(_ question: String, chapterText: String, selectionContext: String?) async throws -> String
    /// Surfaces up to `count` candidate key sentences for smart highlights.
    func suggestHighlights(from text: String, count: Int) async throws -> [String]
}

// MARK: - Error

public enum OnDeviceAIError: Error, Sendable {
    /// The model is not available on this device / OS / flag state.
    case unavailable(OnDeviceAIAvailability)
    /// The model generated an empty or unusable response.
    case emptyResponse
    /// The chapter text passed as grounding context was empty.
    case noContext
    /// A generation-time error surfaced by FoundationModels.
    case generationFailed(String)
}

// MARK: - Live implementation (requires FoundationModels SDK)

#if canImport(FoundationModels)
import FoundationModels

/// The production on-device AI service backed by `SystemLanguageModel`.
///
/// Only compiled when `FoundationModels` is in the SDK (Xcode 26+).
/// All entry points first check ``availability``; if not `.available` they
/// throw ``OnDeviceAIError/unavailable(_:)`` — callers degrade silently.
///
/// Every prompt is grounded in the caller-supplied chapter text to prevent
/// hallucination. Text is truncated to ``maxContextCharacters`` before
/// being inserted into the prompt.
@available(iOS 26, macOS 26, *)
public actor OnDeviceAIService: OnDeviceAIProviding {

    // MARK: - Configuration

    /// Maximum characters of chapter text included in any single prompt.
    /// ~4 000 chars ≈ ~1 000 tokens — leaves headroom for instructions + response.
    public static let maxContextCharacters = 4_000

    // MARK: - State

    private let flag: OnDeviceFeatureFlag

    // MARK: - Init

    public init(flag: OnDeviceFeatureFlag = OnDeviceFeatureFlag()) {
        self.flag = flag
    }

    // MARK: - Availability

    public var availability: OnDeviceAIAvailability {
        guard flag.isEnabled else { return .unavailableFeatureDisabled }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailableDeviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailableNotEnabled
        case .unavailable(.modelNotReady):
            return .unavailableModelNotReady
        case .unavailable:
            return .unavailableUnknown
        }
    }

    // MARK: - Generation

    public func summarizeChapter(title: String, text: String) async throws -> String {
        let state = await availability
        guard state.isAvailable else { throw OnDeviceAIError.unavailable(state) }
        guard !text.isEmpty else { throw OnDeviceAIError.noContext }

        let context = text.truncatedForAI(maxCharacters: Self.maxContextCharacters)
        let instructions = """
        You are a concise book-learning assistant. Summarise the provided chapter in 3–5 clear \
        sentences. Focus only on the key insight and its practical application. \
        Use the chapter text verbatim for facts — do not add information not present in the text. \
        Output plain prose, no headings or bullets.
        """
        let prompt = """
        Chapter: "\(title)"

        Chapter text:
        \(context)

        Write a 3–5 sentence summary of this chapter.
        """
        return try await generate(instructions: instructions, prompt: prompt)
    }

    public func explainHighlight(_ highlight: String, chapterText: String) async throws -> String {
        let state = await availability
        guard state.isAvailable else { throw OnDeviceAIError.unavailable(state) }
        guard !highlight.isEmpty else { throw OnDeviceAIError.noContext }

        let context = chapterText.truncatedForAI(maxCharacters: 2_000)
        let instructions = """
        You are a clear, friendly book-learning assistant. Explain the highlighted passage in \
        simple, everyday language that a non-expert can understand. Stay grounded in the chapter \
        text — do not speculate beyond what is written. Keep the explanation to 2–3 sentences.
        """
        let prompt = """
        Highlighted passage:
        "\(highlight)"

        Chapter context:
        \(context)

        Explain the passage simply in 2–3 sentences.
        """
        return try await generate(instructions: instructions, prompt: prompt)
    }

    public func answerQuestion(
        _ question: String,
        chapterText: String,
        selectionContext: String?
    ) async throws -> String {
        let state = await availability
        guard state.isAvailable else { throw OnDeviceAIError.unavailable(state) }
        guard !chapterText.isEmpty else { throw OnDeviceAIError.noContext }

        let context = chapterText.truncatedForAI(maxCharacters: Self.maxContextCharacters)
        let selectionNote = selectionContext.map { "\n\nSelected passage: \"\($0)\"" } ?? ""
        let instructions = """
        You are a book-learning assistant answering questions about a chapter the user has \
        downloaded offline. Answer ONLY based on the provided chapter text — never invent \
        facts. If the text does not contain enough information, say so plainly. Keep answers \
        concise (3–5 sentences).
        """
        let prompt = """
        Chapter text:
        \(context)\(selectionNote)

        Question: \(question)
        """
        return try await generate(instructions: instructions, prompt: prompt)
    }

    public func suggestHighlights(from text: String, count: Int = 3) async throws -> [String] {
        let state = await availability
        guard state.isAvailable else { throw OnDeviceAIError.unavailable(state) }
        guard !text.isEmpty else { throw OnDeviceAIError.noContext }

        let context = text.truncatedForAI(maxCharacters: 3_000)
        let instructions = """
        You are a reading-assistant that identifies the most insightful sentences from a chapter. \
        Return exactly \(count) candidate sentences worth highlighting, each on its own line \
        starting with "- ". Use verbatim sentences from the text — do not paraphrase or invent.
        """
        let prompt = """
        Chapter text:
        \(context)

        List the \(count) most insightful sentences worth highlighting.
        """
        let raw = try await generate(instructions: instructions, prompt: prompt)
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw OnDeviceAIError.emptyResponse }
        return Array(lines.prefix(count))
    }

    // MARK: - Private helpers

    private func generate(instructions: String, prompt: String) async throws -> String {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw OnDeviceAIError.emptyResponse }
            return trimmed
        } catch let error as OnDeviceAIError {
            throw error
        } catch {
            throw OnDeviceAIError.generationFailed(error.localizedDescription)
        }
    }
}

#endif // canImport(FoundationModels)

// MARK: - Unavailable stub (pre-iOS 26 / pre-macOS 26 / flag-off)

/// A no-op ``OnDeviceAIProviding`` used when the feature is unavailable.
///
/// Every call throws `.unavailable` so callers never block or error the UI —
/// they simply degrade (hide the entry point).
public actor UnavailableOnDeviceAIService: OnDeviceAIProviding {
    private let reason: OnDeviceAIAvailability

    public init(reason: OnDeviceAIAvailability = .unavailableOSVersion) {
        self.reason = reason
    }

    public var availability: OnDeviceAIAvailability { reason }

    public func summarizeChapter(title: String, text: String) async throws -> String {
        throw OnDeviceAIError.unavailable(reason)
    }

    public func explainHighlight(_ highlight: String, chapterText: String) async throws -> String {
        throw OnDeviceAIError.unavailable(reason)
    }

    public func answerQuestion(
        _ question: String,
        chapterText: String,
        selectionContext: String?
    ) async throws -> String {
        throw OnDeviceAIError.unavailable(reason)
    }

    public func suggestHighlights(from text: String, count: Int) async throws -> [String] {
        throw OnDeviceAIError.unavailable(reason)
    }
}

// MARK: - Factory

/// Returns the best available ``OnDeviceAIProviding`` implementation for the current device.
///
/// On iOS 26+ / macOS 26+ with Apple Intelligence available and the feature flag on:
/// returns a live ``OnDeviceAIService``.
/// Otherwise returns ``UnavailableOnDeviceAIService`` so callers degrade silently.
public func makeOnDeviceAIService(
    flag: OnDeviceFeatureFlag = OnDeviceFeatureFlag()
) -> any OnDeviceAIProviding {
    guard flag.isEnabled else {
        return UnavailableOnDeviceAIService(reason: .unavailableFeatureDisabled)
    }
    #if canImport(FoundationModels)
    if #available(iOS 26, macOS 26, *) {
        return OnDeviceAIService(flag: flag)
    }
    #endif
    return UnavailableOnDeviceAIService(reason: .unavailableOSVersion)
}

// MARK: - String helper

extension String {
    /// Truncates the string to `maxCharacters`, appending "…" if cut.
    func truncatedForAI(maxCharacters: Int) -> String {
        guard count > maxCharacters else { return self }
        return String(prefix(maxCharacters)) + "…"
    }
}
