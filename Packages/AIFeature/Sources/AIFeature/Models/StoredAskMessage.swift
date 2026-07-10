import Foundation

/// A persisted Q&A exchange for one book session, stored as part of a
/// ``CachedAskThread`` JSON blob.
///
/// This is the on-disk representation. Convert to ``AskMessage`` for display
/// via ``asAskMessage``.
public struct StoredAskMessage: Codable, Sendable, Identifiable {
    public let id: String
    public let question: String
    public let selectionContext: String?
    public let answer: String
    public let citations: [Int]
    public let isOnDeviceAnswer: Bool
    public let askedAt: Date
    /// True when the user has pinned/saved this exchange to their notebook.
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        question: String,
        selectionContext: String?,
        answer: String,
        citations: [Int],
        isOnDeviceAnswer: Bool = false,
        askedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.question = question
        self.selectionContext = selectionContext
        self.answer = answer
        self.citations = citations
        self.isOnDeviceAnswer = isOnDeviceAnswer
        self.askedAt = askedAt
        self.isPinned = isPinned
    }
}

// MARK: - Conversion

extension StoredAskMessage {
    /// Creates a transient ``AskMessage`` for display from this persistent record.
    public func asAskMessage() -> AskMessage {
        AskMessage(
            id: UUID(uuidString: id) ?? UUID(),
            question: question,
            selectionContext: selectionContext,
            answer: answer,
            citations: citations,
            isOnDeviceAnswer: isOnDeviceAnswer
        )
    }
}

extension AskMessage {
    /// Creates a ``StoredAskMessage`` from this transient message.
    public func toStored(askedAt: Date = Date()) -> StoredAskMessage {
        StoredAskMessage(
            id: id.uuidString,
            question: question,
            selectionContext: selectionContext,
            answer: answer,
            citations: citations,
            isOnDeviceAnswer: isOnDeviceAnswer,
            askedAt: askedAt
        )
    }
}
