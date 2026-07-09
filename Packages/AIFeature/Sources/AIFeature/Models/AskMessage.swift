import Foundation

/// A single Q&A exchange in the "Ask the book" thread.
///
/// Stored in-memory per book session; not persisted to disk in P6.1
/// (full persistence is P6.7).
public struct AskMessage: Sendable, Identifiable {
    public let id: UUID
    /// The question the user typed.
    public let question: String
    /// Optional excerpt the user had selected when the sheet was opened;
    /// was sent as grounding context for this answer.
    public let selectionContext: String?
    /// The server-generated answer (may contain Markdown inline syntax).
    public let answer: String
    /// Chapter numbers cited as supporting evidence.
    public let citations: [Int]
    /// True when the answer was generated on-device (offline, no network).
    /// The UI labels these answers to distinguish them from server responses.
    public let isOnDeviceAnswer: Bool

    public init(
        id: UUID = UUID(),
        question: String,
        selectionContext: String?,
        answer: String,
        citations: [Int],
        isOnDeviceAnswer: Bool = false
    ) {
        self.id = id
        self.question = question
        self.selectionContext = selectionContext
        self.answer = answer
        self.citations = citations
        self.isOnDeviceAnswer = isOnDeviceAnswer
    }
}
