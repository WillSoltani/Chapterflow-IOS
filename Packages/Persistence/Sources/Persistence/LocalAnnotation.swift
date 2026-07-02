import Foundation
import SwiftData

/// A local annotation (highlight, note, or bookmark) persisted in SwiftData.
///
/// Synced write-through to the notebook API when online.
/// Queued via ``PendingAnnotationUpload`` and retried when offline.
@Model
public final class LocalAnnotation {
    @Attribute(.unique) public var annotationId: String
    public var bookId: String
    public var chapterId: String
    /// One of: "highlight", "note", "bookmark"
    public var type: String
    /// JSON-encoded AnnotationAnchor. Nil for standalone bookmarks.
    public var anchorJSON: String?
    /// Raw value of the highlight colour (e.g. "yellow"). Nil for notes/bookmarks.
    public var colorRaw: String?
    /// User-written text for notes. Nil for highlights/bookmarks.
    public var content: String?
    /// The quoted passage at annotation time. Nil for bookmarks with no selection.
    public var snippet: String?
    public var createdAt: Date
    /// One of: "pending", "synced", "failed"
    public var syncState: String
    /// Server-assigned entry ID returned by POST /book/me/notebook.
    public var serverEntryId: String?

    public init(
        annotationId: String = UUID().uuidString,
        bookId: String,
        chapterId: String,
        type: String,
        anchorJSON: String? = nil,
        colorRaw: String? = nil,
        content: String? = nil,
        snippet: String? = nil,
        createdAt: Date = Date(),
        syncState: String = "pending",
        serverEntryId: String? = nil
    ) {
        self.annotationId = annotationId
        self.bookId = bookId
        self.chapterId = chapterId
        self.type = type
        self.anchorJSON = anchorJSON
        self.colorRaw = colorRaw
        self.content = content
        self.snippet = snippet
        self.createdAt = createdAt
        self.syncState = syncState
        self.serverEntryId = serverEntryId
    }
}

/// An offline upload ticket for an annotation that could not be synced immediately.
///
/// Retried when the app regains connectivity.
/// A lightweight pre-P3.4 offline outbox — offline writes must not crash.
@Model
public final class PendingAnnotationUpload {
    @Attribute(.unique) public var uploadId: String
    /// The ``LocalAnnotation/annotationId`` this ticket corresponds to.
    public var annotationId: String
    /// JSON body for POST /book/me/notebook.
    public var requestJSON: String
    public var retryCount: Int
    public var nextRetryAt: Date

    public init(
        uploadId: String = UUID().uuidString,
        annotationId: String,
        requestJSON: String,
        retryCount: Int = 0,
        nextRetryAt: Date = Date()
    ) {
        self.uploadId = uploadId
        self.annotationId = annotationId
        self.requestJSON = requestJSON
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
    }
}
