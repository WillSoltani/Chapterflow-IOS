#if DEBUG
import Foundation
import Persistence

/// In-memory fake for Previews and unit tests.
@MainActor
public final class FakeAnnotationRepository: AnnotationRepository {
    private var store: [LocalAnnotation] = []

    public init(seed: [LocalAnnotation] = []) {
        self.store = seed
    }

    public func loadAnnotations(bookId: String, chapterId: String) async throws -> [LocalAnnotation] {
        store.filter { $0.bookId == bookId && $0.chapterId == chapterId }
    }

    public func addHighlight(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor,
        color: HighlightColor
    ) async throws -> LocalAnnotation {
        let ann = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "highlight",
            anchorJSON: anchor.asJSON(),
            colorRaw: color.rawValue,
            snippet: anchor.snippet,
            syncState: "synced"
        )
        store.append(ann)
        return ann
    }

    public func addNote(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor?,
        content: String
    ) async throws -> LocalAnnotation {
        let ann = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "note",
            anchorJSON: anchor?.asJSON(),
            content: content,
            snippet: anchor?.snippet,
            syncState: "synced"
        )
        store.append(ann)
        return ann
    }

    public func toggleBookmark(bookId: String, chapterId: String) async throws -> LocalAnnotation? {
        if let existing = store.first(where: { $0.type == "bookmark" && $0.bookId == bookId && $0.chapterId == chapterId }) {
            store.removeAll { $0.annotationId == existing.annotationId }
            return nil
        }
        let bm = LocalAnnotation(bookId: bookId, chapterId: chapterId, type: "bookmark", syncState: "synced")
        store.append(bm)
        return bm
    }

    public func deleteAnnotation(_ annotation: LocalAnnotation) async throws {
        store.removeAll { $0.annotationId == annotation.annotationId }
    }

    public func retryPendingUploads() async {}
}
#endif
