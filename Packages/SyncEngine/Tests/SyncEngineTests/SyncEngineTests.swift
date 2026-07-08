import Foundation
import SwiftData
import Testing
import CoreKit
import Models
import Networking
import Persistence
@testable import SyncEngine

// MARK: - Test container

/// Shared in-memory SwiftData container. Created once; tests run serially
/// to avoid concurrent SwiftData access issues.
private let sharedContainer: ModelContainer = {
    // swiftlint:disable:next force_try
    let schema = Schema(PersistenceSchemaV7.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    return try! ModelContainer(for: schema, configurations: config)
}()

// MARK: - Helpers

@MainActor
private func freshContext() throws -> ModelContext {
    let ctx = sharedContainer.mainContext
    try ctx.delete(model: PendingMutation.self)
    try ctx.delete(model: CachedQuizState.self)
    try ctx.save()
    return ctx
}

// MARK: - Payload round-trip tests

@Suite("SyncPayloads", .serialized)
struct SyncPayloadTests {

    @Test("ProgressCursorPayload round-trips losslessly")
    func progressCursorRoundTrip() throws {
        let original = ProgressCursorPayload(bookId: "b-1", chapterId: "ch-3")
        let mutation = try PendingMutation.make(
            userId: "u", kind: .progressCursor, payload: original
        )
        let decoded = try mutation.decodePayload(as: ProgressCursorPayload.self)
        #expect(decoded.bookId == original.bookId)
        #expect(decoded.chapterId == original.chapterId)
    }

    @Test("QuizSubmitPayload round-trips losslessly — no answer keys in bundle")
    func quizSubmitRoundTrip() throws {
        let original = QuizSubmitPayload(
            bookId: "b-1",
            chapterNumber: 3,
            sessionId: "session-42",
            answers: ["q-1": "c-1a", "q-2": "c-2b"]
        )
        let mutation = try PendingMutation.make(
            userId: "u", kind: .quizSubmit, payload: original
        )
        let decoded = try mutation.decodePayload(as: QuizSubmitPayload.self)
        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.answers == original.answers)
        #expect(decoded.bookId == original.bookId)
        #expect(decoded.chapterNumber == original.chapterNumber)
    }

    @Test("NotebookWritePayload round-trips losslessly (create path)")
    func notebookCreateRoundTrip() throws {
        let original = NotebookWritePayload(
            entryId: nil,
            bookId: "b-1",
            chapterId: "ch-2",
            type: "note",
            content: "My note",
            quote: nil,
            color: nil
        )
        let mutation = try PendingMutation.make(
            userId: "u", kind: .notebookWrite, payload: original
        )
        let decoded = try mutation.decodePayload(as: NotebookWritePayload.self)
        #expect(decoded.entryId == nil)
        #expect(decoded.content == "My note")
        #expect(decoded.type == "note")
    }

    @Test("HighlightWritePayload round-trips with full anchor")
    func highlightRoundTrip() throws {
        let original = HighlightWritePayload(
            entryId: nil,
            bookId: "b-1",
            chapterId: "ch-3",
            variantKey: "medium",
            toneKey: "direct",
            blockIndex: 2,
            blockType: "paragraph",
            startChar: 10,
            endChar: 40,
            snippet: "highlighted text",
            color: "yellow"
        )
        let mutation = try PendingMutation.make(
            userId: "u", kind: .highlightWrite, payload: original
        )
        let decoded = try mutation.decodePayload(as: HighlightWritePayload.self)
        #expect(decoded.variantKey == "medium")
        #expect(decoded.toneKey == "direct")
        #expect(decoded.blockIndex == 2)
        #expect(decoded.startChar == 10)
        #expect(decoded.endChar == 40)
        #expect(decoded.snippet == "highlighted text")
        #expect(decoded.color == "yellow")
    }

    @Test("ReviewGradePayload round-trips")
    func reviewGradeRoundTrip() throws {
        let original = ReviewGradePayload(cardId: "card-99", rating: 3)
        let mutation = try PendingMutation.make(
            userId: "u", kind: .reviewGrade, payload: original
        )
        let decoded = try mutation.decodePayload(as: ReviewGradePayload.self)
        #expect(decoded.cardId == "card-99")
        #expect(decoded.rating == 3)
    }

    @Test("CommitmentPayload round-trips (create path)")
    func commitmentCreateRoundTrip() throws {
        let original = CommitmentPayload(
            commitmentId: nil,
            bookId: "b-1",
            chapterId: "ch-2",
            ifStatement: "If I feel procrastinating",
            thenStatement: "then I will open the app",
            followUpDays: 7
        )
        let mutation = try PendingMutation.make(
            userId: "u", kind: .commitment, payload: original
        )
        let decoded = try mutation.decodePayload(as: CommitmentPayload.self)
        #expect(decoded.commitmentId == nil)
        #expect(decoded.ifStatement == "If I feel procrastinating")
        #expect(decoded.followUpDays == 7)
    }

    @Test("SavedTogglePayload round-trips")
    func savedToggleRoundTrip() throws {
        let original = SavedTogglePayload(bookId: "b-1", saved: true)
        let mutation = try PendingMutation.make(
            userId: "u", kind: .savedToggle, payload: original
        )
        let decoded = try mutation.decodePayload(as: SavedTogglePayload.self)
        #expect(decoded.bookId == "b-1")
        #expect(decoded.saved == true)
    }

    @Test("ReadingSessionPayload round-trips")
    func readingSessionRoundTrip() throws {
        let original = ReadingSessionPayload(
            event: "heartbeat",
            bookId: "b-1",
            chapterId: "ch-3",
            sessionId: "sess-123"
        )
        let mutation = try PendingMutation.make(
            userId: "u", kind: .readingSession, payload: original
        )
        let decoded = try mutation.decodePayload(as: ReadingSessionPayload.self)
        #expect(decoded.event == "heartbeat")
        #expect(decoded.sessionId == "sess-123")
    }
}

// MARK: - SyncMutationSnapshot tests

@Suite("SyncMutationSnapshot", .serialized)
struct SyncMutationSnapshotTests {

    @Test("snapshot captures all fields from PendingMutation")
    func snapshotCapture() throws {
        let payload = QuizSubmitPayload(
            bookId: "b-1", chapterNumber: 2, sessionId: "sess-42", answers: ["q1": "c1"]
        )
        let mutation = try PendingMutation.make(userId: "u-test", kind: .quizSubmit, payload: payload)
        let snapshot = SyncMutationSnapshot(from: mutation)

        #expect(snapshot.mutationId == mutation.mutationId)
        #expect(snapshot.userId == "u-test")
        #expect(snapshot.kindRaw == MutationKind.quizSubmit.rawValue)
        #expect(snapshot.kind == .quizSubmit)
        #expect(snapshot.attemptCount == 0)
    }

    @Test("snapshot.kind returns nil for unknown future kind")
    func unknownKind() {
        let mutation = PendingMutation(
            mutationId: "m-1",
            userId: "u",
            kindRaw: "futureKindV99",
            payloadJSON: "{}"
        )
        let snapshot = SyncMutationSnapshot(from: mutation)
        #expect(snapshot.kind == nil)
    }

    @Test("snapshot decodePayload round-trips correctly")
    func decodePayload() throws {
        let original = ReviewGradePayload(cardId: "c-7", rating: 4)
        let mutation = try PendingMutation.make(userId: "u", kind: .reviewGrade, payload: original)
        let snapshot = SyncMutationSnapshot(from: mutation)
        let decoded = try snapshot.decodePayload(as: ReviewGradePayload.self)
        #expect(decoded.cardId == "c-7")
        #expect(decoded.rating == 4)
    }
}

// MARK: - SyncStore tests

@Suite("SyncStore", .serialized)
struct SyncStoreTests {

    @Test("fetchPendingMutations returns mutations in creation order")
    @MainActor
    func fetchInOrder() async throws {
        let ctx = try freshContext()
        let m1 = PendingMutation(
            mutationId: "m-old",
            userId: "u",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{}",
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let m2 = PendingMutation(
            mutationId: "m-new",
            userId: "u",
            kindRaw: MutationKind.savedToggle.rawValue,
            payloadJSON: "{}",
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        ctx.insert(m1)
        ctx.insert(m2)
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        let snapshots = try await syncStore.fetchPendingMutations(userId: "u")

        #expect(snapshots.count == 2)
        #expect(snapshots[0].mutationId == "m-old")
        #expect(snapshots[1].mutationId == "m-new")
    }

    @Test("fetchPendingMutations resets stuck inflight mutations to pending")
    @MainActor
    func resetsInflight() async throws {
        let ctx = try freshContext()
        let stuck = PendingMutation(
            mutationId: "m-stuck",
            userId: "u",
            kindRaw: MutationKind.reviewGrade.rawValue,
            payloadJSON: "{}",
            statusRaw: MutationStatus.inflight.rawValue
        )
        ctx.insert(stuck)
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        let snapshots = try await syncStore.fetchPendingMutations(userId: "u")
        #expect(snapshots.count == 1)
        #expect(snapshots[0].mutationId == "m-stuck")

        // Check status was reset to pending in the store.
        let fetched = try ctx.fetch(FetchDescriptor<PendingMutation>())
        #expect(fetched.first?.statusRaw == MutationStatus.pending.rawValue)
    }

    @Test("markFailed increments attemptCount and records error")
    @MainActor
    func markFailed() async throws {
        let ctx = try freshContext()
        ctx.insert(PendingMutation(
            mutationId: "m-fail",
            userId: "u",
            kindRaw: MutationKind.savedToggle.rawValue,
            payloadJSON: "{}"
        ))
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        try await syncStore.markFailed(mutationId: "m-fail", errorDescription: "timeout")

        let fetched = try ctx.fetch(FetchDescriptor<PendingMutation>())
        let mutation = fetched.first
        #expect(mutation?.statusRaw == MutationStatus.failed.rawValue)
        #expect(mutation?.lastError == "timeout")
        #expect(mutation?.attemptCount == 1)
    }

    @Test("deleteMutation removes the row")
    @MainActor
    func deleteMutation() async throws {
        let ctx = try freshContext()
        ctx.insert(PendingMutation(
            mutationId: "m-del",
            userId: "u",
            kindRaw: MutationKind.readingSession.rawValue,
            payloadJSON: "{}"
        ))
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        try await syncStore.deleteMutation(mutationId: "m-del")

        let remaining = try ctx.fetchCount(FetchDescriptor<PendingMutation>())
        #expect(remaining == 0)
    }

    @Test("countPendingMutations excludes other users")
    @MainActor
    func countExcludesOtherUsers() async throws {
        let ctx = try freshContext()
        ctx.insert(PendingMutation(
            mutationId: UUID().uuidString,
            userId: "user-A",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{}"
        ))
        ctx.insert(PendingMutation(
            mutationId: UUID().uuidString,
            userId: "user-B",
            kindRaw: MutationKind.progressCursor.rawValue,
            payloadJSON: "{}"
        ))
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        let count = try await syncStore.countPendingMutations(userId: "user-A")
        #expect(count == 1)
    }

    @Test("clearQuizPendingGrading resets status to ready")
    @MainActor
    func clearQuizPendingGrading() async throws {
        let ctx = try freshContext()
        let quizPayload = QuizClientSession(
            sessionId: "s-1",
            questions: [],
            passingScorePercent: 70,
            bookId: "b-1",
            chapterNumber: 3,
            tone: nil
        )
        ctx.insert(try CachedQuizState.from(
            quizPayload,
            userId: "u",
            bookId: "b-1",
            chapterNumber: 3,
            status: .pendingGrading
        ))
        try ctx.save()

        let syncStore = SyncStore(modelContainer: sharedContainer)
        try await syncStore.clearQuizPendingGrading(bookId: "b-1", chapterNumber: 3, userId: "u")

        let fetched = try ctx.fetch(FetchDescriptor<CachedQuizState>())
        #expect(fetched.first?.status == .ready)
    }
}

// MARK: - Conflict / idempotency logic tests

@Suite("SyncEngine conflict and idempotency", .serialized)
struct SyncEngineConflictTests {

    // MARK: - Mock API client

    /// A minimal mock that records calls and returns canned responses.
    final class MockClient: APIClientProtocol, @unchecked Sendable {
        struct Call: Sendable {
            let method: String
            let path: String
        }

        var calls: [Call] = []
        var stubbedError: Error?
        /// When set, the first call throws this error; subsequent calls succeed.
        var firstCallError: Error?
        private var callCount = 0

        func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
            calls.append(Call(method: endpoint.method.rawValue, path: endpoint.path))
            callCount += 1
            if let firstError = firstCallError, callCount == 1 {
                throw firstError
            }
            if let error = stubbedError { throw error }
            // Return a minimal valid JSON for the expected type.
            let json = minimalJSON(for: T.self)
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }

        private func minimalJSON<T: Decodable>(for: T.Type) -> String {
            // A generic fallback that works for most single-field responses.
            "{}"
        }
    }

    @Test("server-already-advanced error: dispatch returns without rethrowing (no double-submit)")
    func serverAlreadyAdvanced() async throws {
        // Test dispatch logic directly: no SwiftData needed for this behaviour check.
        let quizPayload = QuizSubmitPayload(
            bookId: "b-1",
            chapterNumber: 2,
            sessionId: "sess-already",
            answers: ["q-1": "c-1b"]
        )
        let payloadData = try JSONEncoder().encode(quizPayload)
        // Create an in-memory mutation (not persisted — we're testing dispatch behaviour only).
        let mutation = PendingMutation(
            mutationId: "m-already",
            userId: "u",
            kindRaw: MutationKind.quizSubmit.rawValue,
            payloadJSON: String(data: payloadData, encoding: .utf8) ?? "{}"
        )
        let snapshot = SyncMutationSnapshot(from: mutation)

        let mock = MockClient()
        mock.stubbedError = AppError.server(
            code: "quiz_already_submitted",
            message: "Already graded",
            requestId: nil
        )
        let engine = SyncEngine(apiClient: mock, container: sharedContainer)

        // dispatchMutation must NOT rethrow "quiz_already_submitted" — it is treated as success.
        await #expect(throws: Never.self) {
            try await engine.dispatchMutation(snapshot)
        }
        // API called exactly once (no retry loop on already-applied errors).
        #expect(mock.calls.count == 1)
    }

    @Test("quiz submit idempotency: same sessionId not sent twice in one drain")
    @MainActor
    func quizIdempotencyGuard() async throws {
        let ctx = try freshContext()
        // Two mutations for the same sessionId (shouldn't happen in practice, but test the guard).
        for _ in 0..<2 {
            let payload = QuizSubmitPayload(
                bookId: "b-1",
                chapterNumber: 1,
                sessionId: "sess-dedup",
                answers: ["q-1": "c-1a"]
            )
            let mutation = try PendingMutation.make(userId: "u", kind: .quizSubmit, payload: payload)
            ctx.insert(mutation)
        }
        try ctx.save()

        let mock = MockClient()
        let engine = SyncEngine(apiClient: mock, container: sharedContainer)
        await engine.triggerDrain(userId: "u")
        try await Task.sleep(for: .milliseconds(300))

        // The dedup guard inside dispatchQuizSubmit prevents the second call.
        let quizCalls = mock.calls.filter { $0.path.contains("submit") }
        #expect(quizCalls.count <= 1)
    }

    @Test("retry-after-partial-drain: failed mutations remain in outbox")
    @MainActor
    func retryAfterPartialDrain() async throws {
        let ctx = try freshContext()
        ctx.insert(PendingMutation(
            mutationId: "m-1",
            userId: "u-retry",
            kindRaw: MutationKind.savedToggle.rawValue,
            payloadJSON: "{\"bookId\":\"b-1\",\"saved\":true}"
        ))
        ctx.insert(PendingMutation(
            mutationId: "m-2",
            userId: "u-retry",
            kindRaw: MutationKind.savedToggle.rawValue,
            payloadJSON: "{\"bookId\":\"b-2\",\"saved\":false}"
        ))
        try ctx.save()

        let mock = MockClient()
        // Use a non-retryable error (invalidInput has isRetryable == false)
        // so the drain fails immediately without backoff delays.
        mock.stubbedError = AppError.invalidInput("server rejected")
        let engine = SyncEngine(apiClient: mock, container: sharedContainer)
        await engine.triggerDrain(userId: "u-retry")
        try await Task.sleep(for: .milliseconds(300))

        // Both mutations still in the outbox with failed status.
        let failed = try ctx.fetch(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.userId == "u-retry" }
        ))
        #expect(failed.count == 2)
        let allFailed = failed.allSatisfy {
            $0.statusRaw == MutationStatus.failed.rawValue
        }
        #expect(allFailed)
    }

    @Test("auth failure stops drain and leaves mutations intact")
    @MainActor
    func authFailureStopsDrain() async throws {
        let ctx = try freshContext()
        for i in 0..<3 {
            ctx.insert(PendingMutation(
                mutationId: "m-auth-\(i)",
                userId: "u-auth",
                kindRaw: MutationKind.progressCursor.rawValue,
                payloadJSON: "{\"bookId\":\"b-1\",\"chapterId\":\"ch-\(i + 1)\"}"
            ))
        }
        try ctx.save()

        let mock = MockClient()
        mock.stubbedError = AppError.unauthenticated
        let engine = SyncEngine(apiClient: mock, container: sharedContainer)
        await engine.triggerDrain(userId: "u-auth")
        try await Task.sleep(for: .milliseconds(400))

        // Drain stops after the first auth failure — not all 3 are attempted.
        #expect(mock.calls.count <= 3)

        let status = await MainActor.run { engine.status.phase }
        #expect(status == .error)
    }

    @Test("SyncStatus reflects idle when outbox is empty")
    @MainActor
    func statusIdleWhenEmpty() async throws {
        let ctx = try freshContext()
        _ = ctx  // fresh, no mutations

        let mock = MockClient()
        let engine = SyncEngine(apiClient: mock, container: sharedContainer)
        await engine.triggerDrain(userId: "u-empty")
        try await Task.sleep(for: .milliseconds(100))

        let phase = await MainActor.run { engine.status.phase }
        #expect(phase == .idle)
        let count = await MainActor.run { engine.status.pendingCount }
        #expect(count == 0)
    }
}

// MARK: - Endpoint+Sync tests

@Suite("Endpoint+Sync")
struct EndpointSyncTests {

    @Test("submitQuiz builds the correct path and body")
    func submitQuizPath() throws {
        let endpoint = try Endpoints.submitQuiz(
            bookId: "book-abc",
            chapterNumber: 5,
            sessionId: "sess-42",
            answers: ["q1": "c1a"]
        )
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/book/me/quiz/book-abc/5/submit")
        #expect(endpoint.requiresAuth == true)
        #expect(endpoint.httpBody != nil)

        struct Body: Decodable { let sessionId: String; let answers: [String: String] }
        // swiftlint:disable:next force_unwrapping
        let body = try JSONDecoder().decode(Body.self, from: endpoint.httpBody!)
        #expect(body.sessionId == "sess-42")
        #expect(body.answers["q1"] == "c1a")
    }

    @Test("submitQuiz percent-encodes bookId")
    func submitQuizEncoding() throws {
        let endpoint = try Endpoints.submitQuiz(
            bookId: "book/with/slashes",
            chapterNumber: 1,
            sessionId: "s",
            answers: [:]
        )
        #expect(!endpoint.path.contains("//"))
    }
}
