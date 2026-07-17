import CoreKit
import Foundation
import Networking
import Persistence
import SwiftData
import Testing
@testable import ReaderFeature

@Suite("Live annotation central journal", .serialized)
@MainActor
struct LiveAnnotationRepositoryTests {
    @Test("highlight creation saves one local row and one deterministic central mutation")
    func highlightCreationUsesOnlyCentralJournal() async throws {
        let container = try makeAnnotationContainer()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)

        let annotation = try await repository.addHighlight(
            bookId: "book-a",
            chapterId: "chapter-a",
            anchor: testAnchor,
            color: .yellow
        )

        let context = container.mainContext
        let localRows = try context.fetch(FetchDescriptor<LocalAnnotation>())
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let legacyUploads = try context.fetch(FetchDescriptor<PendingAnnotationUpload>())
        let mutation = try #require(mutations.first)
        let payload = try mutation.decodePayload(as: HighlightWritePayload.self)

        #expect(localRows.count == 1)
        #expect(localRows.first?.annotationId == annotation.annotationId)
        #expect(mutations.count == 1)
        #expect(mutation.userId == "account-a")
        #expect(mutation.mutationId == AnnotationMutationID.create(
            localAnnotationId: annotation.annotationId
        ))
        #expect(payload.localAnnotationId == annotation.annotationId)
        #expect(legacyUploads.isEmpty)
        #expect(await probe.fireCount == 1)
    }

    @Test("notes and bookmarks use the same central create rule")
    func notesAndBookmarksUseCentralJournal() async throws {
        let container = try makeAnnotationContainer()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)

        let note = try await repository.addNote(
            bookId: "book-a",
            chapterId: "chapter-a",
            anchor: testAnchor,
            content: "private note"
        )
        let bookmark = try #require(
            try await repository.toggleBookmark(bookId: "book-a", chapterId: "chapter-b")
        )

        let mutations = try container.mainContext.fetch(FetchDescriptor<PendingMutation>())
        let noteMutation = try #require(mutations.first {
            $0.mutationId == AnnotationMutationID.create(localAnnotationId: note.annotationId)
        })
        let bookmarkMutation = try #require(mutations.first {
            $0.mutationId == AnnotationMutationID.create(localAnnotationId: bookmark.annotationId)
        })
        let notePayload = try noteMutation.decodePayload(as: NotebookWritePayload.self)
        let bookmarkPayload = try bookmarkMutation.decodePayload(as: NotebookWritePayload.self)

        #expect(mutations.count == 2)
        #expect(notePayload.localAnnotationId == note.annotationId)
        #expect(notePayload.anchor?.snippet == testAnchor.snippet)
        #expect(bookmarkPayload.localAnnotationId == bookmark.annotationId)
        #expect(bookmarkPayload.type == "bookmark")
        #expect(await probe.fireCount == 2)
    }

    @Test("save failure rolls back both local row and central mutation")
    func saveFailureRollsBackBothRows() async throws {
        let container = try makeAnnotationContainer(allowsSave: false)
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)

        do {
            _ = try await repository.addNote(
                bookId: "book-a",
                chapterId: "chapter-a",
                anchor: nil,
                content: "private note"
            )
            Issue.record("Read-only SwiftData configuration unexpectedly saved")
        } catch {
            // Expected: commitContext rolls the main context back.
        }

        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<LocalAnnotation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(await probe.fireCount == 0)
    }

    @Test("synced delete creates a hidden tombstone and central delete mutation")
    func syncedDeleteCreatesHiddenTombstone() async throws {
        let container = try makeAnnotationContainer()
        let context = container.mainContext
        let annotation = LocalAnnotation(
            annotationId: "annotation-a",
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note",
            syncState: LocalAnnotationSyncState.synced.rawValue,
            serverEntryId: "entry-a"
        )
        context.insert(annotation)
        try context.save()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)
        let storedAnnotation = try #require(
            try await repository.loadAnnotations(bookId: "book-a", chapterId: "chapter-a").first
        )

        try await repository.deleteAnnotation(storedAnnotation)

        let validationContext = ModelContext(container)
        let rawRows = try validationContext.fetch(FetchDescriptor<LocalAnnotation>())
        let visibleRows = try await repository.loadAnnotations(
            bookId: "book-a",
            chapterId: "chapter-a"
        )
        let mutations = try validationContext.fetch(FetchDescriptor<PendingMutation>())
        let mutation = try #require(mutations.first)
        let payload = try mutation.decodePayload(as: NotebookDeletePayload.self)
        #expect(rawRows.first?.syncStatus == .pendingDelete)
        #expect(visibleRows.isEmpty)
        #expect(mutation.mutationId == "annotation-delete:annotation-a")
        #expect(payload == NotebookDeletePayload(
            localAnnotationId: "annotation-a",
            serverEntryId: "entry-a"
        ))
        #expect(await probe.fireCount == 1)
    }

    @Test("never-sent local delete removes its create mutation with zero new drain")
    func neverSentDeleteRemovesCreateAndLocalRow() async throws {
        let container = try makeAnnotationContainer()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)
        let annotation = try await repository.addNote(
            bookId: "book-a",
            chapterId: "chapter-a",
            anchor: nil,
            content: "private note"
        )

        try await repository.deleteAnnotation(annotation)

        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<LocalAnnotation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(await probe.fireCount == 1)
    }

    @Test("attempted create becomes hidden pending delete until reconciliation")
    func attemptedCreateDeleteDoesNotDiscardInflightWork() async throws {
        let container = try makeAnnotationContainer()
        let context = container.mainContext
        let annotation = LocalAnnotation(
            annotationId: "annotation-inflight",
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note"
        )
        let payload = NotebookWritePayload(
            localAnnotationId: annotation.annotationId,
            bookId: annotation.bookId,
            chapterId: annotation.chapterId,
            type: "note",
            content: annotation.content
        )
        let mutation = try PendingMutation.make(
            mutationId: AnnotationMutationID.create(localAnnotationId: annotation.annotationId),
            userId: "account-a",
            kind: .notebookWrite,
            payload: payload
        )
        mutation.statusRaw = MutationStatus.inflight.rawValue
        context.insert(annotation)
        context.insert(mutation)
        try context.save()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)
        let storedAnnotation = try #require(
            try await repository.loadAnnotations(bookId: "book-a", chapterId: "chapter-a").first
        )

        try await repository.deleteAnnotation(storedAnnotation)

        let validationContext = ModelContext(container)
        let storedRows = try validationContext.fetch(FetchDescriptor<LocalAnnotation>())
        #expect(storedRows.first?.syncStatus == .pendingDelete)
        #expect(try validationContext.fetchCount(FetchDescriptor<PendingMutation>()) == 1)
        #expect(await probe.fireCount == 1)
    }

    @Test("valid legacy upload migrates once and repeated operations are idempotent")
    func validLegacyUploadMigratesOnce() async throws {
        let container = try makeAnnotationContainer()
        let context = container.mainContext
        let annotation = LocalAnnotation(
            annotationId: "legacy-annotation",
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note"
        )
        let request = NotebookEntryRequest(
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note"
        )
        context.insert(annotation)
        let requestJSON = try #require(String(
            data: try JSONEncoder().encode(request),
            encoding: .utf8
        ))
        context.insert(PendingAnnotationUpload(
            annotationId: annotation.annotationId,
            requestJSON: requestJSON
        ))
        try context.save()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)

        _ = try await repository.loadAnnotations(bookId: "book-a", chapterId: "chapter-a")
        _ = try await repository.loadAnnotations(bookId: "book-a", chapterId: "chapter-a")

        let legacyUploads = try context.fetch(FetchDescriptor<PendingAnnotationUpload>())
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(legacyUploads.isEmpty)
        #expect(mutations.count == 1)
        #expect(mutations.first?.mutationId == "annotation-create:legacy-annotation")
        #expect(mutations.first?.userId == "account-a")
        #expect(await probe.fireCount == 1)
    }

    @Test("malformed and missing-local legacy bytes remain unchanged")
    func unsafeLegacyRowsRemainUnchanged() async throws {
        let container = try makeAnnotationContainer()
        let context = container.mainContext
        context.insert(LocalAnnotation(
            annotationId: "malformed-annotation",
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note"
        ))
        let malformed = "not-json::PRIVATE_BYTES"
        let missingRequest = NotebookEntryRequest(
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "bookmark"
        )
        let missingJSON = try #require(String(
            data: try JSONEncoder().encode(missingRequest),
            encoding: .utf8
        ))
        context.insert(PendingAnnotationUpload(
            uploadId: "malformed",
            annotationId: "malformed-annotation",
            requestJSON: malformed
        ))
        context.insert(PendingAnnotationUpload(
            uploadId: "missing",
            annotationId: "missing-annotation",
            requestJSON: missingJSON
        ))
        try context.save()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe)

        _ = try await repository.loadAnnotations(bookId: "book-a", chapterId: "chapter-a")

        let uploads = try context.fetch(FetchDescriptor<PendingAnnotationUpload>())
        #expect(Set(uploads.map(\.requestJSON)) == Set([malformed, missingJSON]))
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(await probe.fireCount == 0)
    }

    @Test("account-private containers prevent B from reading or queuing A annotations")
    func accountContainersIsolateAnnotations() async throws {
        let containerA = try makeAnnotationContainer()
        let containerB = try makeAnnotationContainer()
        let repositoryA = makeRepository(
            container: containerA,
            accountID: "account-a",
            probe: SyncTriggerProbe()
        )
        let repositoryB = makeRepository(
            container: containerB,
            accountID: "account-b",
            probe: SyncTriggerProbe()
        )

        _ = try await repositoryA.addNote(
            bookId: "book-a",
            chapterId: "chapter-a",
            anchor: nil,
            content: "private note"
        )
        let rowsB = try await repositoryB.loadAnnotations(
            bookId: "book-a",
            chapterId: "chapter-a"
        )

        #expect(rowsB.isEmpty)
        #expect(try containerB.mainContext.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        let mutationA = try #require(
            containerA.mainContext.fetch(FetchDescriptor<PendingMutation>()).first
        )
        #expect(mutationA.userId == "account-a")
    }

    @Test("scope invalidation prevents stale annotation commit and trigger")
    func scopeInvalidationPreventsCommit() async throws {
        let container = try makeAnnotationContainer()
        let permit = SessionWorkPermit()
        permit.invalidate()
        let probe = SyncTriggerProbe()
        let repository = makeRepository(container: container, probe: probe, permit: permit)

        do {
            _ = try await repository.addNote(
                bookId: "book-a",
                chapterId: "chapter-a",
                anchor: nil,
                content: "private note"
            )
            Issue.record("Invalidated scope unexpectedly committed")
        } catch is CancellationError {
            // Expected.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<LocalAnnotation>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(await probe.fireCount == 0)
    }
}

private actor SyncTriggerProbe {
    private(set) var fireCount = 0

    func fire() {
        fireCount += 1
    }
}

@MainActor
private func makeRepository(
    container: ModelContainer,
    accountID: String = "account-a",
    probe: SyncTriggerProbe,
    permit: SessionWorkPermit = SessionWorkPermit()
) -> LiveAnnotationRepository {
    LiveAnnotationRepository(
        container: container,
        accountID: accountID,
        triggerSync: { await probe.fire() },
        workPermit: permit
    )
}

@MainActor
private func makeAnnotationContainer(allowsSave: Bool = true) throws -> ModelContainer {
    let schema = Schema(PersistenceSchemaV8.models)
    if !allowsSave {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        _ = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL)
        )
        let readOnly = ModelConfiguration(schema: schema, url: storeURL, allowsSave: false)
        return try ModelContainer(for: schema, configurations: readOnly)
    }
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: configuration)
}

private let testAnchor = AnnotationAnchor(
    variantKey: "medium",
    toneKey: "direct",
    blockIndex: 0,
    blockType: "paragraph",
    startChar: 0,
    endChar: 4,
    snippet: "text"
)
