import CoreKit
import Foundation
import Networking
import Persistence
import SwiftData
import Testing
@testable import SyncEngine
@Suite("Explicit dispatch outcomes", .serialized)
struct ExplicitDispatchOutcomeTests {
    @Test("applied deletes exactly once")
    @MainActor
    func appliedDispatchDeletesExactlyOnce() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(id: "applied", in: context)
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")
        await engine.drainAndWait(userId: "account-a")

        #expect(fetchMutation("applied", from: context) == nil)
        #expect(await client.callCount == 1)
    }

    @Test("a verified already-applied outcome deletes exactly once")
    @MainActor
    func alreadyAppliedOutcomeDeletesExactlyOnce() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let mutation = insertSavedToggle(id: "already-applied", in: context)
        try context.save()
        let snapshot = SyncMutationSnapshot(from: mutation)
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        let firstDelete = try await engine.resolveDispatchOutcome(.alreadyApplied, for: snapshot)
        let repeatedDelete = try await engine.resolveDispatchOutcome(.alreadyApplied, for: snapshot)

        #expect(firstDelete)
        #expect(!repeatedDelete)
        #expect(fetchMutation("already-applied", from: context) == nil)
        #expect(await client.callCount == 0)
    }

    @Test("unknown kind is retained in quarantine without dispatch")
    @MainActor
    func unknownKindIsQuarantined() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let originalPayload = "{\"opaque\":true,\"marker\":\"PRIVATE_PAYLOAD\"}"
        context.insert(PendingMutation(
            mutationId: "unknown-kind",
            userId: "account-a",
            kindRaw: "future-mutation-kind",
            payloadJSON: originalPayload
        ))
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("unknown-kind", from: context))
        #expect(mutation.status == .quarantined)
        #expect(mutation.lastError == MutationQuarantineReason.unknownKind.safeCode)
        #expect(mutation.payloadJSON == originalPayload)
        #expect(await client.callCount == 0)
    }

    @Test("malformed payload is retained in quarantine without changing its bytes")
    @MainActor
    func malformedPayloadIsQuarantined() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let originalPayload = "not-json::PRIVATE_PAYLOAD"
        context.insert(PendingMutation(
            mutationId: "malformed-payload",
            userId: "account-a",
            kindRaw: MutationKind.savedToggle.rawValue,
            payloadJSON: originalPayload
        ))
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("malformed-payload", from: context))
        #expect(mutation.status == .quarantined)
        #expect(mutation.lastError == MutationQuarantineReason.malformedPayload.safeCode)
        #expect(mutation.payloadJSON == originalPayload)
        #expect(!(mutation.lastError?.contains("PRIVATE_PAYLOAD") ?? true))
        #expect(await client.callCount == 0)
    }

    @Test("incomplete commitment is retained in quarantine without changing its bytes")
    @MainActor
    func incompleteCommitmentIsQuarantined() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let queuedMutation = try PendingMutation.make(
            userId: "account-a",
            kind: .commitment,
            payload: CommitmentPayload(bookId: "book-a", chapterId: "chapter-a")
        )
        let mutationID = queuedMutation.mutationId
        let originalPayload = queuedMutation.payloadJSON
        context.insert(queuedMutation)
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)
        await engine.drainAndWait(userId: "account-a")
        let mutation = try #require(fetchMutation(mutationID, from: context))
        #expect(mutation.status == .quarantined)
        #expect(mutation.lastError == MutationQuarantineReason.missingRequiredField.safeCode)
        #expect(mutation.payloadJSON == originalPayload)
        let updatePayload = CommitmentPayload(commitmentId: "commitment-a", bookId: "book-a", chapterId: "chapter-a")
        let incompleteUpdate = try PendingMutation.make(userId: "account-a", kind: .commitment, payload: updatePayload)
        let updateOutcome = try await engine.dispatchMutation(SyncMutationSnapshot(from: incompleteUpdate))
        #expect(updateOutcome == .quarantined(.missingRequiredField))
        #expect(await client.callCount == 0)
    }

    @Test("local quiz duplicate ambiguity is quarantined without a second request")
    @MainActor
    func localDuplicateAmbiguityIsQuarantined() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let payload = QuizSubmitPayload(
            bookId: "book-a",
            chapterNumber: 2,
            sessionId: "shared-session",
            answers: ["question-a": "choice-a"]
        )
        let first = try PendingMutation.make(
            userId: "account-a",
            kind: .quizSubmit,
            payload: payload,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        first.mutationId = "quiz-first"
        let duplicate = try PendingMutation.make(
            userId: "account-a",
            kind: .quizSubmit,
            payload: payload,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        duplicate.mutationId = "quiz-duplicate"
        context.insert(first)
        context.insert(duplicate)
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)
        await engine.drainAndWait(userId: "account-a")
        #expect(fetchMutation("quiz-first", from: context) == nil)
        let retained = try #require(fetchMutation("quiz-duplicate", from: context))
        #expect(retained.status == .quarantined)
        #expect(retained.lastError == MutationQuarantineReason.ambiguousLocalDuplicate.safeCode)
        #expect(await client.callCount == 1)
    }

    @Test("retryable error remains durable after bounded retries")
    @MainActor
    func retryableErrorRemainsDurable() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        context.insert(PendingMutation(mutationId: "retryable", userId: "account-a", kindRaw: MutationKind.quizSubmit.rawValue, payloadJSON: "{\"bookId\":\"book-a\",\"chapterNumber\":1,\"sessionId\":\"retry-session\",\"answers\":{\"question-a\":\"choice-a\"}}"))
        try context.save()
        let client = OutcomeRecordingClient(stubbedError: .offline)
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("retryable", from: context))
        #expect(mutation.status == .failed)
        #expect(mutation.attemptCount == 1)
        #expect(mutation.lastError == MutationFailureCode.offline.rawValue)
        #expect(await client.callCount == 3)
    }

    @Test("terminal error remains durable and persists only a closed safe code")
    @MainActor
    func terminalErrorRemainsDurable() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(id: "terminal", in: context)
        try context.save()
        let injectedMessage = "PRIVATE_SERVER_MESSAGE"
        let client = OutcomeRecordingClient(stubbedError: .invalidInput(injectedMessage))
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("terminal", from: context))
        #expect(mutation.status == .failed)
        #expect(mutation.lastError == MutationFailureCode.invalidInput.rawValue)
        #expect(!(mutation.lastError?.contains(injectedMessage) ?? true))
        #expect(await client.callCount == 1)
    }

    @Test("auth error stops the drain and retains later rows")
    @MainActor
    func authErrorStopsDrain() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(
            id: "auth-first",
            createdAt: Date(timeIntervalSince1970: 1_000),
            in: context
        )
        insertSavedToggle(
            id: "auth-second",
            bookID: "book-b",
            createdAt: Date(timeIntervalSince1970: 2_000),
            in: context
        )
        try context.save()
        let client = OutcomeRecordingClient(stubbedError: .unauthenticated)
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let first = try #require(fetchMutation("auth-first", from: context))
        let second = try #require(fetchMutation("auth-second", from: context))
        #expect(first.status == .failed)
        #expect(first.lastError == MutationFailureCode.authentication.rawValue)
        #expect(second.status == .pending)
        #expect(await client.callCount == 1)
    }

    @Test("cancellation before dispatch retains a pending mutation")
    @MainActor
    func cancellationBeforeDispatchRetainsMutation() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(id: "cancelled-before-dispatch", in: context)
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)
        let gate = CancellationStartGate()
        let task = Task {
            await gate.suspend()
            await engine.drainAndWait(userId: "account-a")
        }
        await gate.waitUntilSuspended()

        task.cancel()
        await gate.release()
        await task.value

        let mutation = try #require(fetchMutation("cancelled-before-dispatch", from: context))
        #expect(mutation.status == .pending)
        #expect(await client.callCount == 0)
    }

    @Test("cancellation after mark-inflight retains and resets on the next lifecycle")
    @MainActor
    func cancellationAfterInflightIsRecoverable() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(id: "cancelled-after-inflight", in: context)
        try context.save()
        let client = CancellationIgnoringClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.triggerDrain(userId: "account-a")
        await client.waitUntilFirstCallStarts()
        let stopTask = Task { await engine.stop() }
        await client.waitUntilCancellationIsObserved()
        await client.releaseFirstCall()
        await stopTask.value

        let interrupted = try #require(fetchMutation("cancelled-after-inflight", from: context))
        #expect(interrupted.status == .inflight)

        await engine.start(userId: "account-a")
        await engine.waitForCurrentDrain()

        #expect(fetchMutation("cancelled-after-inflight", from: context) == nil)
        #expect(await client.callCount == 2)
        await engine.stop()
    }

    @Test("quarantined rows are excluded from later automatic drains")
    @MainActor
    func quarantinedRowsAreExcludedFromNextDrain() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let originalPayload = "{\"opaque\":\"PRIVATE_PAYLOAD\"}"
        context.insert(PendingMutation(
            mutationId: "quarantine-once",
            userId: "account-a",
            kindRaw: "future-kind",
            payloadJSON: originalPayload
        ))
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")
        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("quarantine-once", from: context))
        #expect(mutation.status == .quarantined)
        #expect(mutation.payloadJSON == originalPayload)
        #expect(mutation.attemptCount == 0)
        #expect(engine.status.phase == .error)
        #expect(engine.status.pendingCount == 1)
        #expect(await client.callCount == 0)
    }

    @Test("response decode failures remain durable failures rather than payload quarantine")
    @MainActor
    func responseDecodeFailureIsNotPayloadQuarantine() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        let inserted = insertSavedToggle(id: "response-decode", in: context)
        let originalPayload = inserted.payloadJSON
        try context.save()
        let client = OutcomeRecordingClient(responseJSON: "not-json::PRIVATE_RESPONSE")
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        let mutation = try #require(fetchMutation("response-decode", from: context))
        #expect(mutation.status == .failed)
        #expect(mutation.lastError == MutationFailureCode.unknown.rawValue)
        #expect(mutation.payloadJSON == originalPayload)
        #expect(!(mutation.lastError?.contains("PRIVATE_RESPONSE") ?? true))
        #expect(await client.callCount == 1)
    }

    @Test("an account A drain cannot fetch account B rows")
    @MainActor
    func accountDrainCannotFetchOtherAccountRows() async throws {
        let container = explicitOutcomeContainer
        let context = try freshExplicitOutcomeContext()
        insertSavedToggle(id: "account-a-row", in: context)
        insertSavedToggle(
            id: "account-b-row",
            userID: "account-b",
            bookID: "book-b",
            in: context
        )
        try context.save()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)

        await engine.drainAndWait(userId: "account-a")

        #expect(fetchMutation("account-a-row", from: context) == nil)
        let accountB = try #require(fetchMutation("account-b-row", from: context))
        #expect(accountB.status == .pending)
        #expect(await client.callCount == 1)
    }

    @Test("every supported mutation kind still returns applied", arguments: MutationKind.allCases)
    @MainActor
    func everySupportedKindDispatches(kind: MutationKind) async throws {
        let container = explicitOutcomeContainer
        _ = try freshExplicitOutcomeContext()
        let client = OutcomeRecordingClient()
        let engine = SyncEngine(apiClient: client, container: container)
        let snapshot = try makeSnapshot(for: kind)

        let outcome = try await engine.dispatchMutation(snapshot)

        #expect(outcome == .applied)
        #expect(await client.callCount == 1)
    }
}

private actor OutcomeRecordingClient: APIClientProtocol {
    private(set) var callCount = 0
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
        _ = endpoint
        callCount += 1
        if let stubbedError {
            throw stubbedError
        }
        return try JSONDecoder().decode(T.self, from: Data(responseJSON.utf8))
    }
}

private actor CancellationIgnoringClient: APIClientProtocol {
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
        if callCount == 1 {
            firstCallStarted = true
            let currentStartWaiters = startWaiters
            startWaiters.removeAll()
            currentStartWaiters.forEach { $0.resume() }

            await withTaskCancellationHandler {
                await waitForFirstCallRelease()
            } onCancel: {
                Task { await self.recordCancellation() }
            }
        }
        return try JSONDecoder().decode(
            T.self,
            from: Data("{\"entryId\":\"entry-test\"}".utf8)
        )
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
        let currentCancellationWaiters = cancellationWaiters
        cancellationWaiters.removeAll()
        currentCancellationWaiters.forEach { $0.resume() }
    }
}

private actor CancellationStartGate {
    private var isSuspended = false
    private var suspension: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspension = continuation
            isSuspended = true
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        suspension?.resume()
        suspension = nil
    }
}

// swiftlint:disable:next force_try
private let explicitOutcomeContainer: ModelContainer = try! {
    let schema = Schema(PersistenceSchemaV7.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: configuration)
}()

@MainActor
private func freshExplicitOutcomeContext() throws -> ModelContext {
    let context = explicitOutcomeContainer.mainContext
    try context.delete(model: PendingMutation.self)
    try context.delete(model: CachedQuizState.self)
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

@discardableResult
@MainActor
private func insertSavedToggle(
    id: String,
    userID: String = "account-a",
    bookID: String = "book-a",
    createdAt: Date = Date(),
    in context: ModelContext
) -> PendingMutation {
    let mutation = PendingMutation(
        mutationId: id,
        userId: userID,
        kindRaw: MutationKind.savedToggle.rawValue,
        payloadJSON: "{\"bookId\":\"\(bookID)\",\"saved\":true}",
        createdAt: createdAt
    )
    context.insert(mutation)
    return mutation
}

private func makeSnapshot(for kind: MutationKind) throws -> SyncMutationSnapshot {
    switch kind {
    case .progressCursor:
        return try makeSnapshot(
            kind: kind,
            payload: ProgressCursorPayload(bookId: "book-a", chapterId: "chapter-a")
        )
    case .quizSubmit:
        return try makeSnapshot(
            kind: kind,
            payload: QuizSubmitPayload(
                bookId: "book-a", chapterNumber: 1, sessionId: "session-a",
                answers: ["question-a": "choice-a"]
            )
        )
    case .notebookWrite:
        return try makeSnapshot(
            kind: kind,
            payload: NotebookWritePayload(
                bookId: "book-a", chapterId: "chapter-a", type: "note", content: "note"
            )
        )
    case .highlightWrite:
        return try makeSnapshot(
            kind: kind,
            payload: HighlightWritePayload(
                bookId: "book-a", chapterId: "chapter-a",
                variantKey: "medium", toneKey: "direct",
                blockIndex: 0, blockType: "paragraph",
                startChar: 0, endChar: 4, snippet: "text", color: "yellow"
            )
        )
    case .reviewGrade:
        return try makeSnapshot(
            kind: kind, payload: ReviewGradePayload(cardId: "card-a", rating: 3)
        )
    case .commitment:
        return try makeSnapshot(
            kind: kind,
            payload: CommitmentPayload(
                bookId: "book-a", chapterId: "chapter-a",
                ifStatement: "if", thenStatement: "then", followUpDays: 7
            )
        )
    case .savedToggle:
        return try makeSnapshot(
            kind: kind, payload: SavedTogglePayload(bookId: "book-a", saved: true)
        )
    case .readingSession:
        return try makeSnapshot(
            kind: kind,
            payload: ReadingSessionPayload(
                event: "end", bookId: "book-a", chapterId: "chapter-a",
                sessionId: "reading-session-a"
            )
        )
    }
}

private func makeSnapshot<Payload: Encodable>(
    kind: MutationKind,
    payload: Payload
) throws -> SyncMutationSnapshot {
    let mutation = try PendingMutation.make(userId: "account-a", kind: kind, payload: payload)
    return SyncMutationSnapshot(from: mutation)
}
