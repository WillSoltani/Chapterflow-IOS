import CoreKit
import Foundation
import Networking
import os
import Persistence
import SwiftData

/// Main-actor reader annotation store backed by the central mutation journal.
///
/// Local rows and their deterministic mutations share one SwiftData save. This
/// repository performs no transport and owns no retry loop; SyncEngine is the
/// sole dispatcher after `triggerSync` is called post-commit.
@MainActor
public final class LiveAnnotationRepository: AnnotationRepository {
    private let container: ModelContainer
    private var context: ModelContext
    private let accountID: String
    private let triggerSync: @Sendable () async -> Void
    private let workPermit: SessionWorkPermit
    private let logger = Logger(subsystem: "com.chapterflow.ios", category: "AnnotationRepo")
    private var didInspectLegacyUploads = false

    public init(
        container: ModelContainer,
        accountID: String,
        triggerSync: @escaping @Sendable () async -> Void,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.container = container
        self.context = ModelContext(container)
        self.accountID = accountID
        self.triggerSync = triggerSync
        self.workPermit = workPermit
    }

    public func loadAnnotations(bookId: String, chapterId: String) async throws -> [LocalAnnotation] {
        try await prepareForOperation()
        let pendingDelete = LocalAnnotationSyncState.pendingDelete.rawValue
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate {
                $0.bookId == bookId
                    && $0.chapterId == chapterId
                    && $0.syncState != pendingDelete
            },
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
        try await prepareForOperation()
        let ticket = try workPermit.begin()
        let annotation = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "highlight",
            anchorJSON: anchor.asJSON(),
            colorRaw: color.rawValue,
            snippet: anchor.snippet,
            syncState: LocalAnnotationSyncState.pending.rawValue
        )
        let payload = HighlightWritePayload(
            localAnnotationId: annotation.annotationId,
            bookId: bookId,
            chapterId: chapterId,
            variantKey: anchor.variantKey,
            toneKey: anchor.toneKey,
            blockIndex: anchor.blockIndex,
            blockType: anchor.blockType,
            startChar: anchor.startChar,
            endChar: anchor.endChar,
            snippet: anchor.snippet,
            color: color.rawValue
        )
        try persistCreate(annotation, payload: .highlight(payload), ticket: ticket)
        await triggerSync()
        return annotation
    }

    public func addNote(
        bookId: String,
        chapterId: String,
        anchor: AnnotationAnchor?,
        content: String
    ) async throws -> LocalAnnotation {
        try await prepareForOperation()
        let ticket = try workPermit.begin()
        let annotation = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "note",
            anchorJSON: anchor?.asJSON(),
            content: content,
            snippet: anchor?.snippet,
            syncState: LocalAnnotationSyncState.pending.rawValue
        )
        let payload = NotebookWritePayload(
            localAnnotationId: annotation.annotationId,
            bookId: bookId,
            chapterId: chapterId,
            type: "note",
            content: content,
            quote: anchor?.snippet,
            anchor: anchor.map(NotebookAnchorPayload.init)
        )
        try persistCreate(annotation, payload: .notebook(payload), ticket: ticket)
        await triggerSync()
        return annotation
    }

    public func toggleBookmark(bookId: String, chapterId: String) async throws -> LocalAnnotation? {
        try await prepareForOperation()
        let ticket = try workPermit.begin()
        let pendingDelete = LocalAnnotationSyncState.pendingDelete.rawValue
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate {
                $0.type == "bookmark"
                    && $0.bookId == bookId
                    && $0.chapterId == chapterId
                    && $0.syncState != pendingDelete
            }
        )
        if let existing = try context.fetch(descriptor).first {
            if try stageDelete(existing, ticket: ticket) {
                await triggerSync()
            }
            return nil
        }

        let annotation = LocalAnnotation(
            bookId: bookId,
            chapterId: chapterId,
            type: "bookmark",
            syncState: LocalAnnotationSyncState.pending.rawValue
        )
        let payload = NotebookWritePayload(
            localAnnotationId: annotation.annotationId,
            bookId: bookId,
            chapterId: chapterId,
            type: "bookmark"
        )
        try persistCreate(annotation, payload: .notebook(payload), ticket: ticket)
        await triggerSync()
        return annotation
    }

    public func deleteAnnotation(_ annotation: LocalAnnotation) async throws {
        try await prepareForOperation()
        let ticket = try workPermit.begin()
        if try stageDelete(annotation, ticket: ticket) {
            await triggerSync()
        }
    }

    private func persistCreate(
        _ annotation: LocalAnnotation,
        payload: AnnotationCreatePayload,
        ticket: UInt64
    ) throws {
        let mutationID = AnnotationMutationID.create(localAnnotationId: annotation.annotationId)
        guard try fetchMutation(mutationID: mutationID) == nil else {
            throw AnnotationJournalFailure.mutationIdentityCollision
        }
        let mutation = try payload.makeMutation(
            mutationID: mutationID,
            accountID: accountID
        )
        try commitContext(ticket: ticket) {
            context.insert(annotation)
            context.insert(mutation)
        }
    }

    /// Returns true when central work remains and a drain should be signalled.
    private func stageDelete(_ annotation: LocalAnnotation, ticket: UInt64) throws -> Bool {
        if let serverEntryID = annotation.serverEntryId {
            return try stageServerDelete(
                annotation,
                serverEntryID: serverEntryID,
                ticket: ticket
            )
        }
        guard annotation.syncStatus != .synced else {
            throw AnnotationJournalFailure.missingServerEntryID
        }

        let createID = AnnotationMutationID.create(localAnnotationId: annotation.annotationId)
        let createMutation = try fetchMutation(mutationID: createID)
        let wasNeverSent = createMutation.map {
            $0.attemptCount == 0 && $0.status != .inflight && $0.status != .failed
        } ?? true

        if wasNeverSent {
            try commitContext(ticket: ticket) {
                if let createMutation {
                    context.delete(createMutation)
                }
                context.delete(annotation)
            }
            return false
        }

        // An inflight/previously attempted create is not an unsent local write.
        // Hide it now; reconciliation will add the delete once the server ID arrives.
        try commitContext(ticket: ticket) {
            annotation.syncStatus = .pendingDelete
        }
        return true
    }

    private func stageServerDelete(
        _ annotation: LocalAnnotation,
        serverEntryID: String,
        ticket: UInt64
    ) throws -> Bool {
        let payload = NotebookDeletePayload(
            localAnnotationId: annotation.annotationId,
            serverEntryId: serverEntryID
        )
        let mutationID = AnnotationMutationID.delete(localAnnotationId: annotation.annotationId)
        let existing = try fetchMutation(mutationID: mutationID)
        guard existing.map({ existingDeleteMatches($0, payload: payload) }) ?? true else {
            throw AnnotationJournalFailure.mutationIdentityCollision
        }
        let mutation = try existing == nil
            ? PendingMutation.make(
                mutationId: mutationID,
                userId: accountID,
                kind: .notebookDelete,
                payload: payload
            )
            : nil

        try commitContext(ticket: ticket) {
            annotation.syncStatus = .pendingDelete
            if let mutation {
                context.insert(mutation)
            }
        }
        return true
    }

    private func existingDeleteMatches(
        _ mutation: PendingMutation,
        payload: NotebookDeletePayload
    ) -> Bool {
        guard mutation.userId == accountID, mutation.kind == .notebookDelete else { return false }
        return (try? mutation.decodePayload(as: NotebookDeletePayload.self)) == payload
    }

    private func prepareForOperation() async throws {
        if try migrateLegacyUploadsIfNeeded() {
            await triggerSync()
        }
    }

    private func migrateLegacyUploadsIfNeeded() throws -> Bool {
        guard !didInspectLegacyUploads else { return false }
        let ticket = try workPermit.begin()
        let uploads = try context.fetch(FetchDescriptor<PendingAnnotationUpload>())
        guard !uploads.isEmpty else {
            didInspectLegacyUploads = true
            return false
        }

        let groups = Dictionary(grouping: uploads, by: \.annotationId)
        var diagnostics = LegacyMigrationDiagnostics()
        var actions: [LegacyMigrationAction] = []
        for upload in uploads {
            guard groups[upload.annotationId]?.count == 1 else {
                diagnostics.ambiguous += 1
                continue
            }
            guard let request = try? JSONDecoder().decode(
                NotebookEntryRequest.self,
                from: Data(upload.requestJSON.utf8)
            ) else {
                diagnostics.malformed += 1
                continue
            }
            guard let annotation = try fetchAnnotation(annotationID: upload.annotationId) else {
                diagnostics.missingLocal += 1
                continue
            }
            guard request.matches(annotation),
                  let payload = AnnotationCreatePayload(request: request, annotation: annotation) else {
                diagnostics.ambiguous += 1
                continue
            }
            do {
                let action = try migrationAction(
                    upload: upload,
                    payload: payload,
                    localAnnotationID: annotation.annotationId
                )
                actions.append(action)
            } catch {
                diagnostics.ambiguous += 1
            }
        }

        if !actions.isEmpty {
            try commitContext(ticket: ticket) {
                for action in actions {
                    if let mutation = action.mutation {
                        context.insert(mutation)
                    }
                    context.delete(action.upload)
                }
            }
        }
        didInspectLegacyUploads = true
        logLegacyDiagnostics(diagnostics)
        return !actions.isEmpty
    }

    private func migrationAction(
        upload: PendingAnnotationUpload,
        payload: AnnotationCreatePayload,
        localAnnotationID: String
    ) throws -> LegacyMigrationAction {
        let mutationID = AnnotationMutationID.create(localAnnotationId: localAnnotationID)
        if let existing = try fetchMutation(mutationID: mutationID) {
            guard payload.matches(existing, accountID: accountID) else {
                throw AnnotationJournalFailure.mutationIdentityCollision
            }
            return LegacyMigrationAction(upload: upload, mutation: nil)
        }
        let mutation = try payload.makeMutation(mutationID: mutationID, accountID: accountID)
        mutation.attemptCount = upload.retryCount
        if upload.retryCount > 0 {
            mutation.statusRaw = MutationStatus.failed.rawValue
        }
        return LegacyMigrationAction(upload: upload, mutation: mutation)
    }

    private func logLegacyDiagnostics(_ diagnostics: LegacyMigrationDiagnostics) {
        if diagnostics.malformed > 0 {
            logger.warning(
                "Legacy annotation rows retained: code=malformed count=\(diagnostics.malformed)"
            )
        }
        if diagnostics.missingLocal > 0 {
            logger.warning(
                "Legacy annotation rows retained: code=missing_local count=\(diagnostics.missingLocal)"
            )
        }
        if diagnostics.ambiguous > 0 {
            logger.warning(
                "Legacy annotation rows retained: code=ambiguous count=\(diagnostics.ambiguous)"
            )
        }
    }

    private func fetchMutation(mutationID: String) throws -> PendingMutation? {
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.mutationId == mutationID }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchAnnotation(annotationID: String) throws -> LocalAnnotation? {
        let descriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate { $0.annotationId == annotationID }
        )
        return try context.fetch(descriptor).first
    }

    private func commitContext(ticket: UInt64, _ mutation: () throws -> Void) throws {
        try workPermit.commit(ticket) {
            do {
                try context.transaction {
                    try mutation()
                    try context.save()
                }
            } catch {
                context.rollback()
                context = ModelContext(container)
                throw error
            }
        }
    }
}

private enum AnnotationJournalFailure: Error {
    case missingServerEntryID
    case mutationIdentityCollision
}

private struct LegacyMigrationDiagnostics {
    var malformed = 0
    var missingLocal = 0
    var ambiguous = 0
}

private struct LegacyMigrationAction {
    let upload: PendingAnnotationUpload
    let mutation: PendingMutation?
}

private enum AnnotationCreatePayload {
    case notebook(NotebookWritePayload)
    case highlight(HighlightWritePayload)

    init?(request: NotebookEntryRequest, annotation: LocalAnnotation) {
        switch request.type {
        case "highlight":
            guard let anchor = request.anchor, let color = request.color else { return nil }
            self = .highlight(HighlightWritePayload(
                localAnnotationId: annotation.annotationId,
                bookId: request.bookId,
                chapterId: request.chapterId,
                variantKey: anchor.variantKey,
                toneKey: anchor.toneKey,
                blockIndex: anchor.blockIndex,
                blockType: anchor.blockType,
                startChar: anchor.startChar,
                endChar: anchor.endChar,
                snippet: anchor.snippet,
                color: color
            ))
        case "note", "bookmark":
            self = .notebook(NotebookWritePayload(
                localAnnotationId: annotation.annotationId,
                bookId: request.bookId,
                chapterId: request.chapterId,
                type: request.type,
                content: request.content,
                quote: request.quote,
                color: request.color,
                anchor: request.anchor.map(NotebookAnchorPayload.init)
            ))
        default:
            return nil
        }
    }

    func makeMutation(mutationID: String, accountID: String) throws -> PendingMutation {
        switch self {
        case .notebook(let payload):
            return try PendingMutation.make(
                mutationId: mutationID,
                userId: accountID,
                kind: .notebookWrite,
                payload: payload
            )
        case .highlight(let payload):
            return try PendingMutation.make(
                mutationId: mutationID,
                userId: accountID,
                kind: .highlightWrite,
                payload: payload
            )
        }
    }

    func matches(_ mutation: PendingMutation, accountID: String) -> Bool {
        guard mutation.userId == accountID else { return false }
        switch self {
        case .notebook(let payload):
            return mutation.kind == .notebookWrite
                && (try? mutation.decodePayload(as: NotebookWritePayload.self)) == payload
        case .highlight(let payload):
            return mutation.kind == .highlightWrite
                && (try? mutation.decodePayload(as: HighlightWritePayload.self)) == payload
        }
    }
}

private extension NotebookAnchorPayload {
    init(_ anchor: AnnotationAnchor) {
        self.init(
            variantKey: anchor.variantKey,
            toneKey: anchor.toneKey,
            blockIndex: anchor.blockIndex,
            blockType: anchor.blockType,
            startChar: anchor.startChar,
            endChar: anchor.endChar,
            snippet: anchor.snippet
        )
    }

    init(_ anchor: NotebookEntryRequest.Anchor) {
        self.init(
            variantKey: anchor.variantKey,
            toneKey: anchor.toneKey,
            blockIndex: anchor.blockIndex,
            blockType: anchor.blockType,
            startChar: anchor.startChar,
            endChar: anchor.endChar,
            snippet: anchor.snippet
        )
    }
}

private extension NotebookEntryRequest {
    func matches(_ annotation: LocalAnnotation) -> Bool {
        guard bookId == annotation.bookId,
              chapterId == annotation.chapterId,
              type == annotation.type else { return false }
        switch type {
        case "highlight":
            return quote == annotation.snippet && color == annotation.colorRaw
        case "note":
            return content == annotation.content && quote == annotation.snippet
        case "bookmark":
            return content == nil
        default:
            return false
        }
    }
}
