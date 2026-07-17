import CoreKit
import Foundation
import Networking
import Persistence
import SwiftData
import Testing
@testable import SyncEngine

@Suite("Annotation journal dispatch", .serialized)
struct AnnotationJournalDispatchTests {
    @Test("offline highlight survives relaunch, reconciles, tombstones, and confirms delete")
    @MainActor
    func hermeticOfflineRelaunchReconnectDeleteFlow() async throws {
        let context = try resetAnnotationJournal()
        insertHighlightCreate(in: context)
        try context.save()

        let relaunchedPending = ModelContext(annotationJournalContainer)
        let pendingAnnotation = try #require(fetchAnnotation(
            "annotation-highlight",
            from: relaunchedPending
        ))
        #expect(pendingAnnotation.syncStatus == .pending)
        #expect(fetchMutation(
            "annotation-create:annotation-highlight",
            from: relaunchedPending
        ) != nil)

        let createClient = AnnotationRecordingClient(
            responseJSON: "{\"entryId\":\"entry-highlight\"}"
        )
        let createEngine = SyncEngine(
            apiClient: createClient,
            container: annotationJournalContainer
        )
        await createEngine.drainAndWait(userId: "account-a")

        let reconciledContext = ModelContext(annotationJournalContainer)
        let reconciled = try #require(fetchAnnotation(
            "annotation-highlight",
            from: reconciledContext
        ))
        #expect(reconciled.serverEntryId == "entry-highlight")
        #expect(reconciled.syncStatus == .synced)
        #expect(fetchMutation(
            "annotation-create:annotation-highlight",
            from: reconciledContext
        ) == nil)

        reconciled.syncStatus = .pendingDelete
        reconciledContext.insert(try makeDeleteMutation(
            localAnnotationID: reconciled.annotationId,
            serverEntryID: "entry-highlight"
        ))
        try reconciledContext.save()

        let relaunchedDelete = ModelContext(annotationJournalContainer)
        let pendingDelete = LocalAnnotationSyncState.pendingDelete.rawValue
        let visibleDescriptor = FetchDescriptor<LocalAnnotation>(
            predicate: #Predicate { $0.syncState != pendingDelete }
        )
        #expect(try relaunchedDelete.fetch(visibleDescriptor).isEmpty)
        #expect(fetchAnnotation("annotation-highlight", from: relaunchedDelete)?.syncStatus == .pendingDelete)
        #expect(fetchMutation(
            "annotation-delete:annotation-highlight",
            from: relaunchedDelete
        ) != nil)

        let deleteClient = AnnotationRecordingClient(responseJSON: "{\"deleted\":true}")
        let deleteEngine = SyncEngine(
            apiClient: deleteClient,
            container: annotationJournalContainer
        )
        await deleteEngine.drainAndWait(userId: "account-a")

        let removedContext = ModelContext(annotationJournalContainer)
        #expect(fetchAnnotation("annotation-highlight", from: removedContext) == nil)
        #expect(fetchMutation(
            "annotation-delete:annotation-highlight",
            from: removedContext
        ) == nil)
        #expect(await createClient.endpoints.first?.method == .post)
        #expect(await deleteClient.endpoints.first?.method == .delete)
        #expect(await deleteClient.endpoints.first?.path == "/book/me/notebook/entry-highlight")
    }

    @Test("successful notebook create reconciles local ID before mutation removal")
    @MainActor
    func successfulCreateReconcilesBeforeRemoval() async throws {
        let context = try resetAnnotationJournal()
        insertNotebookCreate(in: context)
        try context.save()
        let client = AnnotationRecordingClient(
            responseJSON: "{\"entryId\":\"entry-created\"}"
        )
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-a")

        let verificationContext = ModelContext(annotationJournalContainer)
        let annotation = try #require(fetchAnnotation(
            "annotation-create",
            from: verificationContext
        ))
        #expect(annotation.serverEntryId == "entry-created")
        #expect(annotation.syncStatus == .synced)
        #expect(fetchMutation(
            "annotation-create:annotation-create",
            from: verificationContext
        ) == nil)
        #expect(await client.callCount == 1)
    }

    @Test("missing local create retains mutation without transport")
    @MainActor
    func missingLocalCreateRetainsMutation() async throws {
        let context = try resetAnnotationJournal()
        let payload = NotebookWritePayload(
            localAnnotationId: "missing-annotation",
            bookId: "book-a",
            chapterId: "chapter-a",
            type: "note",
            content: "private note"
        )
        context.insert(try PendingMutation.make(
            mutationId: "annotation-create:missing-annotation",
            userId: "account-a",
            kind: .notebookWrite,
            payload: payload
        ))
        try context.save()
        let client = AnnotationRecordingClient()
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-a")

        let verificationContext = ModelContext(annotationJournalContainer)
        let retained = try #require(fetchMutation(
            "annotation-create:missing-annotation",
            from: verificationContext
        ))
        #expect(retained.status == .failed)
        #expect(await client.callCount == 0)
    }

    @Test("create reconciliation preserves pending delete and queues delete")
    @MainActor
    func createReconciliationQueuesRequestedDelete() async throws {
        let context = try resetAnnotationJournal()
        insertNotebookCreate(syncState: .pendingDelete, in: context)
        try context.save()
        let client = AnnotationRecordingClient(
            responseJSON: "{\"entryId\":\"entry-created\"}"
        )
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-a")

        let verificationContext = ModelContext(annotationJournalContainer)
        let annotation = try #require(fetchAnnotation(
            "annotation-create",
            from: verificationContext
        ))
        let deleteMutation = try #require(fetchMutation(
            "annotation-delete:annotation-create",
            from: verificationContext
        ))
        #expect(annotation.serverEntryId == "entry-created")
        #expect(annotation.syncStatus == .pendingDelete)
        #expect(deleteMutation.kind == .notebookDelete)
        #expect(fetchMutation(
            "annotation-create:annotation-create",
            from: verificationContext
        ) == nil)
    }

    @Test("network, auth, and server delete failures retain tombstone and mutation")
    @MainActor
    func deleteFailuresRemainDurable() async throws {
        let failures: [(AppError, MutationFailureCode)] = [
            (.offline, .offline),
            (.unauthenticated, .authentication),
            (.server(code: "server", message: "PRIVATE_MESSAGE", requestId: nil), .server),
        ]

        for (error, expectedCode) in failures {
            let context = try resetAnnotationJournal()
            insertAnnotationDelete(in: context)
            try context.save()
            let client = AnnotationRecordingClient(stubbedError: error)
            let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

            await engine.drainAndWait(userId: "account-a")

            let verificationContext = ModelContext(annotationJournalContainer)
            let annotation = try #require(fetchAnnotation(
                "annotation-delete",
                from: verificationContext
            ))
            let mutation = try #require(fetchMutation(
                "annotation-delete:annotation-delete",
                from: verificationContext
            ))
            #expect(annotation.syncStatus == .pendingDelete)
            #expect(mutation.status == .failed)
            #expect(mutation.lastError == expectedCode.rawValue)
            #expect(!(mutation.lastError?.contains("PRIVATE_MESSAGE") ?? true))
            #expect(await client.callCount >= 1)
        }
    }

    @Test("unknown notebook delete 404 remains a retained failure")
    @MainActor
    func notebookDelete404RemainsDurable() async throws {
        let context = try resetAnnotationJournal()
        insertAnnotationDelete(in: context)
        try context.save()
        let client = AnnotationRecordingClient(stubbedError: .notFound)
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-a")

        let verificationContext = ModelContext(annotationJournalContainer)
        let annotation = try #require(fetchAnnotation(
            "annotation-delete",
            from: verificationContext
        ))
        let mutation = try #require(fetchMutation(
            "annotation-delete:annotation-delete",
            from: verificationContext
        ))
        #expect(annotation.syncStatus == .pendingDelete)
        #expect(mutation.status == .failed)
        #expect(mutation.lastError == MutationFailureCode.notFound.rawValue)
        #expect(await client.callCount == 1)
    }

    @Test("cancelled notebook delete retains tombstone and mutation")
    @MainActor
    func cancelledNotebookDeleteRemainsDurable() async throws {
        let context = try resetAnnotationJournal()
        insertAnnotationDelete(in: context)
        try context.save()
        let client = AnnotationCancellationClient()
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.triggerDrain(userId: "account-a")
        await client.waitUntilFirstCallStarts()
        let stopTask = Task { await engine.stop() }
        await client.waitUntilCancellationIsObserved()
        await client.releaseFirstCall()
        await stopTask.value

        let verificationContext = ModelContext(annotationJournalContainer)
        let annotation = try #require(fetchAnnotation(
            "annotation-delete",
            from: verificationContext
        ))
        let mutation = try #require(fetchMutation(
            "annotation-delete:annotation-delete",
            from: verificationContext
        ))
        #expect(annotation.syncStatus == .pendingDelete)
        #expect(mutation.status == .inflight)
        #expect(await client.callCount == 1)
    }

    @Test("confirmed delete uses exact endpoint before removing local state")
    @MainActor
    func confirmedDeleteRemovesLocalState() async throws {
        let context = try resetAnnotationJournal()
        insertAnnotationDelete(in: context)
        try context.save()
        let client = AnnotationRecordingClient(responseJSON: "{\"deleted\":true}")
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-a")

        let endpoints = await client.endpoints
        let verificationContext = ModelContext(annotationJournalContainer)
        #expect(endpoints.count == 1)
        #expect(endpoints.first?.method == .delete)
        #expect(endpoints.first?.path == "/book/me/notebook/entry-delete")
        #expect(fetchAnnotation("annotation-delete", from: verificationContext) == nil)
        #expect(fetchMutation(
            "annotation-delete:annotation-delete",
            from: verificationContext
        ) == nil)
    }

    @Test("account B cannot drain account A annotation mutations")
    @MainActor
    func accountDrainCannotCrossAccounts() async throws {
        let context = try resetAnnotationJournal()
        insertNotebookCreate(in: context)
        try context.save()
        let client = AnnotationRecordingClient()
        let engine = SyncEngine(apiClient: client, container: annotationJournalContainer)

        await engine.drainAndWait(userId: "account-b")

        let verificationContext = ModelContext(annotationJournalContainer)
        let mutation = try #require(fetchMutation(
            "annotation-create:annotation-create",
            from: verificationContext
        ))
        #expect(mutation.status == .pending)
        #expect(await client.callCount == 0)
    }
}

private actor AnnotationRecordingClient: APIClientProtocol {
    private(set) var callCount = 0
    private(set) var endpoints: [Endpoint] = []
    private let stubbedError: AppError?
    private let responseJSON: String

    init(
        stubbedError: AppError? = nil,
        responseJSON: String = "{\"entryId\":\"entry-test\"}"
    ) {
        self.stubbedError = stubbedError
        self.responseJSON = responseJSON
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        endpoints.append(endpoint)
        callCount += 1
        if let stubbedError {
            throw stubbedError
        }
        return try JSONDecoder().decode(T.self, from: Data(responseJSON.utf8))
    }
}

private actor AnnotationCancellationClient: APIClientProtocol {
    private(set) var callCount = 0
    private var firstCallStarted = false
    private var cancellationObserved = false
    private var firstCallReleased = false
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        _ = endpoint
        callCount += 1
        firstCallStarted = true
        let currentStartWaiters = startWaiters
        startWaiters.removeAll()
        currentStartWaiters.forEach { $0.resume() }

        await withTaskCancellationHandler {
            await waitForFirstCallRelease()
        } onCancel: {
            Task { await self.recordCancellation() }
        }
        return try JSONDecoder().decode(T.self, from: Data("{\"deleted\":true}".utf8))
    }

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancellationIsObserved() async {
        guard !cancellationObserved else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        firstCallReleased = true
        firstCallContinuation?.resume()
        firstCallContinuation = nil
    }

    private func waitForFirstCallRelease() async {
        guard !firstCallReleased else { return }
        await withCheckedContinuation { continuation in
            firstCallContinuation = continuation
        }
    }

    private func recordCancellation() {
        cancellationObserved = true
        let currentWaiters = cancellationWaiters
        cancellationWaiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }
}

// swiftlint:disable:next force_try
private let annotationJournalContainer: ModelContainer = try! {
    let schema = Schema(PersistenceSchemaV8.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: configuration)
}()

@MainActor
private func resetAnnotationJournal() throws -> ModelContext {
    let context = annotationJournalContainer.mainContext
    try context.delete(model: PendingMutation.self)
    try context.delete(model: LocalAnnotation.self)
    try context.save()
    return context
}

@MainActor
private func fetchMutation(_ mutationID: String, from context: ModelContext) -> PendingMutation? {
    let descriptor = FetchDescriptor<PendingMutation>(
        predicate: #Predicate { $0.mutationId == mutationID }
    )
    return try? context.fetch(descriptor).first
}

@MainActor
private func fetchAnnotation(_ annotationID: String, from context: ModelContext) -> LocalAnnotation? {
    let descriptor = FetchDescriptor<LocalAnnotation>(
        predicate: #Predicate { $0.annotationId == annotationID }
    )
    return try? context.fetch(descriptor).first
}

@MainActor
private func insertHighlightCreate(in context: ModelContext) {
    let annotation = LocalAnnotation(
        annotationId: "annotation-highlight",
        bookId: "book-a",
        chapterId: "chapter-a",
        type: "highlight",
        anchorJSON: "{\"variantKey\":\"medium\"}",
        colorRaw: "yellow",
        snippet: "text"
    )
    let payload = HighlightWritePayload(
        localAnnotationId: annotation.annotationId,
        bookId: annotation.bookId,
        chapterId: annotation.chapterId,
        variantKey: "medium",
        toneKey: "direct",
        blockIndex: 0,
        blockType: "paragraph",
        startChar: 0,
        endChar: 4,
        snippet: "text",
        color: "yellow"
    )
    // swiftlint:disable:next force_try
    let mutation = try! PendingMutation.make(
        mutationId: AnnotationMutationID.create(localAnnotationId: annotation.annotationId),
        userId: "account-a",
        kind: .highlightWrite,
        payload: payload
    )
    context.insert(annotation)
    context.insert(mutation)
}

@MainActor
private func insertNotebookCreate(
    syncState: LocalAnnotationSyncState = .pending,
    in context: ModelContext
) {
    let annotation = LocalAnnotation(
        annotationId: "annotation-create",
        bookId: "book-a",
        chapterId: "chapter-a",
        type: "note",
        content: "private note",
        syncState: syncState.rawValue
    )
    let payload = NotebookWritePayload(
        localAnnotationId: annotation.annotationId,
        bookId: annotation.bookId,
        chapterId: annotation.chapterId,
        type: annotation.type,
        content: annotation.content
    )
    // swiftlint:disable:next force_try
    let mutation = try! PendingMutation.make(
        mutationId: AnnotationMutationID.create(localAnnotationId: annotation.annotationId),
        userId: "account-a",
        kind: .notebookWrite,
        payload: payload
    )
    context.insert(annotation)
    context.insert(mutation)
}

@MainActor
private func insertAnnotationDelete(in context: ModelContext) {
    let annotation = LocalAnnotation(
        annotationId: "annotation-delete",
        bookId: "book-a",
        chapterId: "chapter-a",
        type: "note",
        content: "private note",
        syncState: LocalAnnotationSyncState.pendingDelete.rawValue,
        serverEntryId: "entry-delete"
    )
    // swiftlint:disable:next force_try
    let mutation = try! makeDeleteMutation(
        localAnnotationID: annotation.annotationId,
        serverEntryID: "entry-delete"
    )
    context.insert(annotation)
    context.insert(mutation)
}

private func makeDeleteMutation(
    localAnnotationID: String,
    serverEntryID: String
) throws -> PendingMutation {
    try PendingMutation.make(
        mutationId: AnnotationMutationID.delete(localAnnotationId: localAnnotationID),
        userId: "account-a",
        kind: .notebookDelete,
        payload: NotebookDeletePayload(
            localAnnotationId: localAnnotationID,
            serverEntryId: serverEntryID
        )
    )
}
