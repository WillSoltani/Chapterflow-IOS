import Foundation
import SwiftData

/// A local annotation (highlight, note, or bookmark) persisted in SwiftData.
///
/// Saved together with a deterministic central ``PendingMutation``. The
/// SyncEngine is the only network/retry owner.
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
    /// Raw value of ``LocalAnnotationSyncState``.
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

/// Local visibility/reconciliation state for a notebook-backed annotation.
///
/// This remains a raw string on ``LocalAnnotation`` for schema compatibility;
/// adding `pendingDelete` therefore requires no SwiftData migration.
public enum LocalAnnotationSyncState: String, Sendable, CaseIterable {
    case pending
    case synced
    case failed
    case pendingDelete
}

extension LocalAnnotation {
    /// Typed state for repository and SyncEngine reconciliation.
    public var syncStatus: LocalAnnotationSyncState {
        get { LocalAnnotationSyncState(rawValue: syncState) ?? .failed }
        set { syncState = newValue.rawValue }
    }

    /// Tombstones stay durable but are excluded from normal reader loads.
    public var isPendingDeletion: Bool {
        syncStatus == .pendingDelete
    }
}

/// An offline upload ticket for an annotation that could not be synced immediately.
///
/// Legacy pre-central-journal upload ticket. New code never creates these rows;
/// valid rows are migrated transactionally and malformed bytes are preserved.
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
