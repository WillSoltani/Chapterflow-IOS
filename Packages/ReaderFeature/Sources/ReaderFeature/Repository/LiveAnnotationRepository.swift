import Foundation
import SwiftData
import Persistence
import Networking
import CoreKit
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
    private let workPermit: SessionWorkPermit
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "AnnotationRepo")

    /// - Parameters:
    ///   - container: The shared `ModelContainer` (use the app's `PersistenceController.container`).
    ///   - apiClient: The live API client with an authenticated token provider.
    public init(
        container: ModelContainer,
        apiClient: any APIClientProtocol,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.container = container
        self.apiClient = apiClient
        self.workPermit = workPermit
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
        let ticket = try workPermit.begin()
        let ann = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "highlight",
            anchorJSON: anchor.asJSON(),
            colorRaw: color.rawValue,
            snippet: anchor.snippet,
            syncState: "pending"
        )
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
        try persistPending(ann, body: body, ticket: ticket)
        try await postQueued(ann, body: body, ticket: ticket)
        return ann
    }

    public func addNote(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor?,
        content: String
    ) async throws -> LocalAnnotation {
        let ticket = try workPermit.begin()
        let ann = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "note",
            anchorJSON: anchor?.asJSON(),
            content: content,
            snippet: anchor?.snippet,
            syncState: "pending"
        )
        let requestAnchor = anchor.map {
            NotebookEntryRequest.Anchor(
                variantKey: $0.variantKey,
                toneKey: $0.toneKey,
                blockIndex: $0.blockIndex,
                blockType: $0.blockType,
                startChar: $0.startChar,
                endChar: $0.endChar,
                snippet: $0.snippet
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
        try persistPending(ann, body: body, ticket: ticket)
        try await postQueued(ann, body: body, ticket: ticket)
        return ann
    }

    public func toggleBookmark(bookId: String, chapterId: String) async throws -> LocalAnnotation? {
        let ticket = try workPermit.begin()
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate {
                $0.type == "bookmark" && $0.bookId == bookId && $0.chapterId == chapterId
            }
        )
        if let existing = try context.fetch(descriptor).first {
            await deleteServerEntry(existing.serverEntryId)
            try commitContext(ticket: ticket) {
                context.delete(existing)
            }
            return nil
        }
        let bm = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "bookmark",
            syncState: "pending"
        )
        let body = NotebookEntryRequest(
            bookId: bm.bookId,
            chapterId: bm.chapterId,
            type: "bookmark"
        )
        try persistPending(bm, body: body, ticket: ticket)
        try await postQueued(bm, body: body, ticket: ticket)
        return bm
    }

    public func deleteAnnotation(_ annotation: LocalAnnotation) async throws {
        let ticket = try workPermit.begin()
        let serverId = annotation.serverEntryId
        try commitContext(ticket: ticket) {
            context.delete(annotation)
        }
        await deleteServerEntry(serverId)
    }

    public func retryPendingUploads() async {
        guard let workTicket = try? workPermit.begin() else { return }
        let now = Date()
        let descriptor = FetchDescriptor<PendingAnnotationUpload>(
            predicate: #Predicate { $0.nextRetryAt <= now }
        )
        guard let pending = try? context.fetch(descriptor) else { return }

        for pendingUpload in pending {
            guard let data = pendingUpload.requestJSON.data(using: .utf8),
                  let request = try? JSONDecoder().decode(NotebookEntryRequest.self, from: data) else {
                logger.warning("Skipping malformed pending upload \(pendingUpload.uploadId)")
                continue
            }
            do {
                let endpoint = try Endpoints.postNotebookEntry(request)
                let response: NotebookCreateResponse = try await apiClient.send(endpoint)
                try commitContext(ticket: workTicket) {
                    let annId = pendingUpload.annotationId
                    let annDescriptor = FetchDescriptor<LocalAnnotation>(
                        predicate: #Predicate { $0.annotationId == annId }
                    )
                    if let ann = try? context.fetch(annDescriptor).first {
                        ann.syncState = "synced"
                        ann.serverEntryId = response.entryId
                    }
                    context.delete(pendingUpload)
                }
            } catch is CancellationError {
                return
            } catch {
                do {
                    try commitContext(ticket: workTicket) {
                        pendingUpload.retryCount += 1
                        let delay = min(60.0, pow(2.0, Double(pendingUpload.retryCount))) * 60
                        pendingUpload.nextRetryAt = Date(timeIntervalSinceNow: delay)
                    }
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - Private upload helpers

    private func persistPending(
        _ ann: LocalAnnotation,
        body: NotebookEntryRequest,
        ticket: UInt64
    ) throws {
        let data = try JSONEncoder().encode(body)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        try commitContext(ticket: ticket) {
            context.insert(ann)
            context.insert(PendingAnnotationUpload(
                annotationId: ann.annotationId,
                requestJSON: json
            ))
        }
    }

    private func postQueued(
        _ ann: LocalAnnotation,
        body: NotebookEntryRequest,
        ticket: UInt64
    ) async throws {
        do {
            let endpoint = try Endpoints.postNotebookEntry(body)
            let response: NotebookCreateResponse = try await apiClient.send(endpoint)
            try commitContext(ticket: ticket) {
                ann.syncState = "synced"
                ann.serverEntryId = response.entryId
                let annotationId = ann.annotationId
                let descriptor = FetchDescriptor<PendingAnnotationUpload>(
                    predicate: #Predicate { $0.annotationId == annotationId }
                )
                if let uploads = try? context.fetch(descriptor) {
                    uploads.forEach { context.delete($0) }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Annotation upload failed, queuing retry: \(error.localizedDescription)")
        }
    }

    private func deleteServerEntry(_ serverId: String?) async {
        guard let serverId else { return }
        let endpoint = Endpoints.deleteNotebookEntry(entryId: serverId)
        do {
            let _: NotebookDeleteResponse = try await apiClient.send(endpoint)
        } catch is CancellationError {
            return
        } catch {
            logger.warning("Failed to delete notebook entry \(serverId): \(error.localizedDescription)")
        }
    }

    /// Keeps the long-lived main context clean when a save fails. Without the
    /// rollback, a later operation could accidentally persist an earlier failed
    /// mutation outside its permit ticket.
    private func commitContext(
        ticket: UInt64,
        _ mutation: () throws -> Void
    ) throws {
        try workPermit.commit(ticket) {
            do {
                try mutation()
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
