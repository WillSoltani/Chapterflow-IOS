import Foundation
import SwiftData

/// An offline outbox entry for a review grade that could not be synced immediately.
///
/// When the user grades a card without network connectivity, the grade is written
/// here and replayed to `POST /book/me/reviews/{cardId}` when connectivity resumes.
/// The server schedule always wins on conflict reconciliation.
@Model
public final class PendingReviewGrade {
    /// Unique ID for this outbox entry (UUID string).
    @Attribute(.unique) public var uploadId: String
    /// The FSRS card being graded.
    public var cardId: String
    /// The user's rating (1=Again, 2=Hard, 3=Good, 4=Easy).
    public var rating: Int
    /// ISO-8601 timestamp when the review happened (used for FSRS elapsed-days calc).
    public var reviewedAt: String
    /// Optimistic stability the client applied locally.
    public var optimisticStability: Double
    /// Optimistic difficulty the client applied locally.
    public var optimisticDifficulty: Double
    /// Optimistic ISO-8601 due date the client computed locally.
    public var optimisticDueAt: String
    /// Number of upload attempts so far.
    public var retryCount: Int
    /// Earliest time to retry (backing off on repeated failures).
    public var nextRetryAt: Date

    public init(
        uploadId: String = UUID().uuidString,
        cardId: String,
        rating: Int,
        reviewedAt: String,
        optimisticStability: Double,
        optimisticDifficulty: Double,
        optimisticDueAt: String,
        retryCount: Int = 0,
        nextRetryAt: Date = Date()
    ) {
        self.uploadId             = uploadId
        self.cardId               = cardId
        self.rating               = rating
        self.reviewedAt           = reviewedAt
        self.optimisticStability  = optimisticStability
        self.optimisticDifficulty = optimisticDifficulty
        self.optimisticDueAt      = optimisticDueAt
        self.retryCount           = retryCount
        self.nextRetryAt          = nextRetryAt
    }
}
