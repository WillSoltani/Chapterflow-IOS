import Foundation
import Persistence

/// The annotation persistence and sync contract.
///
/// Declared `@MainActor` so that callers pass `LocalAnnotation` (a SwiftData
/// `@Model` reference type, not `Sendable`) without crossing actor boundaries.
@MainActor
public protocol AnnotationRepository: AnyObject {
    /// Loads all annotations for the given chapter from the local store.
    func loadAnnotations(bookId: String, chapterId: String) async throws -> [LocalAnnotation]

    /// Creates a highlight annotation and queues a sync to the notebook API.
    func addHighlight(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor,
        color: HighlightColor
    ) async throws -> LocalAnnotation

    /// Creates a note annotation (optionally attached to an anchor).
    func addNote(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor?,
        content: String
    ) async throws -> LocalAnnotation

    /// Toggles the bookmark for the chapter: creates one if absent, deletes if present.
    /// Returns the newly created bookmark, or `nil` if the bookmark was deleted.
    func toggleBookmark(bookId: String, chapterId: String) async throws -> LocalAnnotation?

    /// Stages a durable local delete; server-confirmed removal is owned by SyncEngine.
    func deleteAnnotation(_ annotation: LocalAnnotation) async throws
}
