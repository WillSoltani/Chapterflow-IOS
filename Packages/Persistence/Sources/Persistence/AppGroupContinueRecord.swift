import Foundation
import SwiftData

/// A SwiftData record in the App Group snapshot container.
///
/// Holds the richer "continue reading" metadata that widgets use to render
/// book cover and chapter context. At most ONE row exists at any time — the
/// single most-recently-read book. ``SharedStateWriter`` is the sole writer.
///
/// - Important: This model lives in the **App Group snapshot container**
///   (`AppGroupSnapshot.store`), which is entirely separate from the main
///   `ChapterFlow.store` managed by ``PersistenceController``. It must
///   **not** appear in ``PersistenceMigrationPlan`` (RF4).
@Model
public final class AppGroupContinueRecord {
    public var bookId: String
    public var bookTitle: String
    public var coverEmoji: String?
    public var coverColor: String?
    public var chapterNumber: Int
    public var progress: Double
    public var updatedAt: Date

    public init(
        bookId: String,
        bookTitle: String,
        coverEmoji: String?,
        coverColor: String?,
        chapterNumber: Int,
        progress: Double,
        updatedAt: Date = Date()
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.coverEmoji = coverEmoji
        self.coverColor = coverColor
        self.chapterNumber = chapterNumber
        self.progress = progress
        self.updatedAt = updatedAt
    }
}
