import Foundation
import SwiftData

/// An offline outbox entry for a scenario submission that could not be synced immediately.
///
/// Created when `POST /book/me/books/{bookId}/chapters/{n}/scenarios` fails with `.offline`.
/// The sync engine retries on reconnect; the server response is authoritative for
/// status and points — never grant locally.
@Model
public final class PendingScenarioUpload {
    @Attribute(.unique) public var uploadId: String
    /// Local placeholder ID assigned before the server ID is known.
    public var localScenarioId: String
    /// The book the scenario is for.
    public var bookId: String
    /// The chapter number the scenario is for.
    public var chapterNumber: Int
    /// JSON-encoded `CreateScenarioRequest` body.
    public var requestJSON: String
    public var retryCount: Int
    public var nextRetryAt: Date
    public var createdAt: Date

    public init(
        uploadId: String = UUID().uuidString,
        localScenarioId: String,
        bookId: String,
        chapterNumber: Int,
        requestJSON: String,
        retryCount: Int = 0,
        nextRetryAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.uploadId = uploadId
        self.localScenarioId = localScenarioId
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.requestJSON = requestJSON
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.createdAt = createdAt
    }
}
