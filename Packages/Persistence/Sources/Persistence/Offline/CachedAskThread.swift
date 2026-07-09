import Foundation
import SwiftData

/// A persisted Q&A thread for one user + book pair.
///
/// All messages for a given `(userId, bookId)` are stored as a single JSON blob
/// so the thread can be fetched and displayed without network access. The blob
/// round-trips through ``StoredAskMessage`` (defined in AIFeature) using a
/// type-erased JSON format, so Persistence doesn't depend on AIFeature.
@Model
public final class CachedAskThread {
    /// Composite unique key: `"userId:bookId"`.
    @Attribute(.unique) public var threadId: String
    public var userId: String
    public var bookId: String
    /// Optional book title kept for attribution in copy/share flows.
    public var bookTitle: String?
    /// JSON-encoded array of message payloads.
    public var messagesJSON: String
    public var messageCount: Int
    public var lastUpdatedAt: Date

    public init(
        threadId: String,
        userId: String,
        bookId: String,
        bookTitle: String? = nil,
        messagesJSON: String = "[]",
        messageCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.threadId = threadId
        self.userId = userId
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.messagesJSON = messagesJSON
        self.messageCount = messageCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}

// MARK: - Factory

extension CachedAskThread {
    public static func makeThreadId(userId: String, bookId: String) -> String {
        "\(userId):\(bookId)"
    }
}
