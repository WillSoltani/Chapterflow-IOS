import Foundation
import SwiftData
import Persistence
import Networking
import os

/// Live implementation of `AnnotationRepository`.
///
/// Write-through: every mutation is persisted locally first (SwiftData), then
/// POSTed to the notebook API. When the network call fails the local record stays
/// with `syncState = "pending"` and a `PendingAnnotationUpload` outbox ticket is
/// created for retry. This means offline annotations never crash and are retried
/// automatically when the app regains connectivity.
@MainActor
public final class LiveAnnotationRepository: AnnotationRepository {
    private let container: ModelContainer
    private let apiClient: any APIClientProtocol
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "AnnotationRepo")

    /// - Parameters:
    ///   - container: The shared `ModelContainer` (use the app's `PersistenceController.container`).
    ///   - apiClient: The live API client with an authenticated token provider.
    public init(container: ModelContainer, apiClient: any APIClientProtocol) {
        self.container = container
        self.apiClient = apiClient
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Protocol conformance

    public func loadAnnotations(bookId: String, chapterId: String) async throws -> [LocalAnnotation] {
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate { $0.bookId == bookId && $0.chapterId == chapterId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
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
            syncState: "pending"
        )
        context.insert(ann)
        try context.save()

        await uploadAnnotation(ann, anchor: anchor, color: color)
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
            syncState: "pending"
        )
        context.insert(ann)
        try context.save()

        await uploadNote(ann, anchor: anchor)
        return ann
    }

    public func toggleBookmark(bookId: String, chapterId: String) async throws -> LocalAnnotation? {
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate {
                $0.type == "bookmark" && $0.bookId == bookId && $0.chapterId == chapterId
            }
        )
        if let existing = try context.fetch(descriptor).first {
            await deleteServerEntry(existing.serverEntryId)
            context.delete(existing)
            try context.save()
            return nil
        }
        let bm = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "bookmark",
            syncState: "pending"
        )
        context.insert(bm)
        try context.save()

        await uploadBookmark(bm)
        return bm
    }

    public func deleteAnnotation(_ annotation: LocalAnnotation) async throws {
        let serverId = annotation.serverEntryId
        context.delete(annotation)
        try context.save()
        await deleteServerEntry(serverId)
    }

    public func retryPendingUploads() async {
        let now = Date()
        let descriptor = FetchDescriptor<PendingAnnotationUpload>(
            predicate: #Predicate { $0.nextRetryAt <= now }
        )
        guard let pending = try? context.fetch(descriptor) else { return }

        for ticket in pending {
            guard let data = ticket.requestJSON.data(using: .utf8),
                  let request = try? JSONDecoder().decode(NotebookEntryRequest.self, from: data) else {
                logger.warning("Skipping malformed pending upload \(ticket.uploadId)")
                continue
            }
            do {
                let endpoint = try Endpoints.postNotebookEntry(request)
                let response: NotebookCreateResponse = try await apiClient.send(endpoint)
                // Mark the local annotation as synced.
                let annId = ticket.annotationId
                let annDescriptor = FetchDescriptor<LocalAnnotation>(
                    predicate: #Predicate { $0.annotationId == annId }
                )
                if let ann = try? context.fetch(annDescriptor).first {
                    ann.syncState = "synced"
                    ann.serverEntryId = response.entryId
                }
                context.delete(ticket)
                try? context.save()
            } catch {
                ticket.retryCount += 1
                let delay = min(60.0, pow(2.0, Double(ticket.retryCount))) * 60
                ticket.nextRetryAt = Date(timeIntervalSinceNow: delay)
                try? context.save()
            }
        }
    }

    // MARK: - Private upload helpers

    private func uploadAnnotation(
        _ ann: LocalAnnotation,
        anchor: AnnotationAnchor,
        color: HighlightColor
    ) async {
        let requestAnchor = NotebookEntryRequest.Anchor(
            variantKey: anchor.variantKey,
            toneKey: anchor.toneKey,
            blockIndex: anchor.blockIndex,
            blockType: anchor.blockType,
            startChar: anchor.startChar,
            endChar: anchor.endChar,
            snippet: anchor.snippet
        )
        let body = NotebookEntryRequest(
            bookId: ann.bookId,
            chapterId: ann.chapterId,
            type: "highlight",
            quote: anchor.snippet,
            color: color.rawValue,
            anchor: requestAnchor
        )
        await postOrQueue(ann, body: body)
    }

    private func uploadNote(_ ann: LocalAnnotation, anchor: AnnotationAnchor?) async {
        var requestAnchor: NotebookEntryRequest.Anchor?
        if let anchor {
            requestAnchor = NotebookEntryRequest.Anchor(
                variantKey: anchor.variantKey,
                toneKey: anchor.toneKey,
                blockIndex: anchor.blockIndex,
                blockType: anchor.blockType,
                startChar: anchor.startChar,
                endChar: anchor.endChar,
                snippet: anchor.snippet
            )
        }
        let body = NotebookEntryRequest(
            bookId: ann.bookId,
            chapterId: ann.chapterId,
            type: "note",
            content: ann.content,
            quote: anchor?.snippet,
            anchor: requestAnchor
        )
        await postOrQueue(ann, body: body)
    }

    private func uploadBookmark(_ ann: LocalAnnotation) async {
        let body = NotebookEntryRequest(
            bookId: ann.bookId,
            chapterId: ann.chapterId,
            type: "bookmark"
        )
        await postOrQueue(ann, body: body)
    }

    private func postOrQueue(_ ann: LocalAnnotation, body: NotebookEntryRequest) async {
        do {
            let endpoint = try Endpoints.postNotebookEntry(body)
            let response: NotebookCreateResponse = try await apiClient.send(endpoint)
            ann.syncState = "synced"
            ann.serverEntryId = response.entryId
            try? context.save()
        } catch {
            logger.warning("Annotation upload failed, queuing retry: \(error.localizedDescription)")
            ann.syncState = "pending"
            if let data = try? JSONEncoder().encode(body),
               let json = String(data: data, encoding: .utf8) {
                let ticket = PendingAnnotationUpload(annotationId: ann.annotationId, requestJSON: json)
                context.insert(ticket)
            }
            try? context.save()
        }
    }

    private func deleteServerEntry(_ serverId: String?) async {
        guard let serverId else { return }
        let endpoint = Endpoints.deleteNotebookEntry(entryId: serverId)
        do {
            let _: NotebookDeleteResponse = try await apiClient.send(endpoint)
        } catch {
            logger.warning("Failed to delete notebook entry \(serverId): \(error.localizedDescription)")
        }
    }
}
