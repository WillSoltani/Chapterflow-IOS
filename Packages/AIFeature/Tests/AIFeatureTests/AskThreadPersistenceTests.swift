import Testing
import Foundation
import SwiftData
@testable import AIFeature
@testable import Persistence

// MARK: - Shared in-memory store

/// One process-wide in-memory ``ModelContainer`` for the whole AIFeature test bundle.
///
/// Building a *second* `ModelContainer` for the same `@Model` classes inside one
/// test process makes CoreData trap with `SIGTRAP` ("multiple NSEntityDescriptions
/// claim the NSManagedObject subclass"). The old per-test `makeInMemoryContext()`
/// created a fresh container on every call, so the crash surfaced as soon as a
/// second test ran. Containers are expensive and must be shared; `ModelContext`s
/// are cheap, so each test gets a fresh, cleared context off the one container.
@MainActor
enum SharedAITestStore {
    static let container: ModelContainer = {
        let schema = Schema(PersistenceSchemaV8.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    /// A fresh context on the shared container with all P6.7-touched tables cleared,
    /// so serialized tests start isolated from one another.
    static func freshContext() -> ModelContext {
        let ctx = ModelContext(container)
        try? ctx.delete(model: CachedAskThread.self)
        try? ctx.delete(model: CachedNotebookEntry.self)
        try? ctx.delete(model: PendingMutation.self)
        try? ctx.save()
        return ctx
    }
}

// MARK: - StoredAskMessage round-trip tests

@Suite("StoredAskMessage")
struct StoredAskMessageTests {

    @Test("AskMessage round-trips through StoredAskMessage losslessly")
    func roundTrip() {
        let original = AskMessage(
            question: "What is the habit loop?",
            selectionContext: "A short excerpt",
            answer: "The habit loop consists of cue, craving, response, and reward.",
            citations: [1, 3],
            isOnDeviceAnswer: false
        )

        let stored = original.toStored(askedAt: Date())
        let recovered = stored.asAskMessage()

        #expect(recovered.question == original.question)
        #expect(recovered.selectionContext == original.selectionContext)
        #expect(recovered.answer == original.answer)
        #expect(recovered.citations == original.citations)
        #expect(recovered.isOnDeviceAnswer == original.isOnDeviceAnswer)
    }

    @Test("StoredAskMessage preserves isPinned flag")
    func isPinnedPreserved() {
        var stored = StoredAskMessage(
            question: "Q",
            selectionContext: nil,
            answer: "A",
            citations: []
        )
        stored.isPinned = true
        #expect(stored.isPinned == true)
        stored.isPinned = false
        #expect(stored.isPinned == false)
    }

    @Test("StoredAskMessage JSON encodes and decodes correctly")
    func jsonRoundTrip() throws {
        let message = StoredAskMessage(
            id: "test-id",
            question: "What is compound growth?",
            selectionContext: nil,
            answer: "1% better every day yields 37× improvement after a year.",
            citations: [1, 2],
            isOnDeviceAnswer: true,
            askedAt: Date(timeIntervalSinceReferenceDate: 0),
            isPinned: true
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(StoredAskMessage.self, from: data)

        #expect(decoded.id == message.id)
        #expect(decoded.question == message.question)
        #expect(decoded.answer == message.answer)
        #expect(decoded.citations == message.citations)
        #expect(decoded.isOnDeviceAnswer == message.isOnDeviceAnswer)
        #expect(decoded.isPinned == message.isPinned)
    }
}

// MARK: - AskThreadStore tests

@Suite("Ask persistence", .serialized)
@MainActor
struct AskThreadStoreTests {

    private func makeInMemoryContext() throws -> ModelContext {
        SharedAITestStore.freshContext()
    }

    @Test("loadMessages returns empty array for unknown book")
    func loadUnknownBook() throws {
        let ctx = try makeInMemoryContext()
        let messages = AskThreadStore.loadMessages(bookId: "unknown", userId: "u1", context: ctx)
        #expect(messages.isEmpty)
    }

    @Test("upsertThread then loadMessages returns the saved messages")
    func upsertAndLoad() throws {
        let ctx = try makeInMemoryContext()
        let messages = [
            StoredAskMessage(
                question: "What is a habit?",
                selectionContext: nil,
                answer: "A routine behaviour.",
                citations: [1]
            ),
            StoredAskMessage(
                question: "How do I build one?",
                selectionContext: nil,
                answer: "Small, consistent steps.",
                citations: [2, 3]
            ),
        ]

        AskThreadStore.upsertThread(
            bookId: "b-habits",
            userId: "u1",
            bookTitle: "Atomic Habits",
            messages: messages,
            context: ctx
        )

        let loaded = AskThreadStore.loadMessages(bookId: "b-habits", userId: "u1", context: ctx)
        #expect(loaded.count == 2)
        #expect(loaded[0].question == "What is a habit?")
        #expect(loaded[1].citations == [2, 3])
    }

    @Test("upsertThread overwrites existing thread for same book/user")
    func upsertOverwrites() throws {
        let ctx = try makeInMemoryContext()

        let first = [StoredAskMessage(question: "Q1", selectionContext: nil, answer: "A1", citations: [])]
        AskThreadStore.upsertThread(bookId: "b-test", userId: "u1", bookTitle: nil, messages: first, context: ctx)

        let updated = [
            StoredAskMessage(question: "Q1", selectionContext: nil, answer: "A1", citations: []),
            StoredAskMessage(question: "Q2", selectionContext: nil, answer: "A2", citations: [1]),
        ]
        AskThreadStore.upsertThread(bookId: "b-test", userId: "u1", bookTitle: "Title", messages: updated, context: ctx)

        let loaded = AskThreadStore.loadMessages(bookId: "b-test", userId: "u1", context: ctx)
        #expect(loaded.count == 2)
        #expect(loaded[1].question == "Q2")

        // Only one CachedAskThread row should exist.
        let count = try ctx.fetchCount(FetchDescriptor<CachedAskThread>())
        #expect(count == 1)
    }

    @Test("updatePinState toggles isPinned for a specific message")
    func updatePinState() throws {
        let ctx = try makeInMemoryContext()
        let msg = StoredAskMessage(
            id: "msg-pin-test",
            question: "Q",
            selectionContext: nil,
            answer: "A",
            citations: []
        )
        AskThreadStore.upsertThread(bookId: "b-pin", userId: "u1", bookTitle: nil, messages: [msg], context: ctx)

        AskThreadStore.updatePinState(messageId: "msg-pin-test", isPinned: true, bookId: "b-pin", userId: "u1", context: ctx)
        let pinned = AskThreadStore.loadMessages(bookId: "b-pin", userId: "u1", context: ctx)
        #expect(pinned.first?.isPinned == true)

        AskThreadStore.updatePinState(messageId: "msg-pin-test", isPinned: false, bookId: "b-pin", userId: "u1", context: ctx)
        let unpinned = AskThreadStore.loadMessages(bookId: "b-pin", userId: "u1", context: ctx)
        #expect(unpinned.first?.isPinned == false)
    }

    @Test("allThreads returns threads sorted by most-recent-first")
    func allThreadsSorted() throws {
        let ctx = try makeInMemoryContext()
        let oldMsg = [StoredAskMessage(question: "Old Q", selectionContext: nil, answer: "Old A", citations: [])]
        let newMsg = [StoredAskMessage(question: "New Q", selectionContext: nil, answer: "New A", citations: [])]

        AskThreadStore.upsertThread(bookId: "b-old", userId: "u1", bookTitle: "Old Book", messages: oldMsg, context: ctx)
        // Small delay so lastUpdatedAt differs.
        Thread.sleep(forTimeInterval: 0.01)
        AskThreadStore.upsertThread(bookId: "b-new", userId: "u1", bookTitle: "New Book", messages: newMsg, context: ctx)

        let threads = AskThreadStore.allThreads(userId: "u1", context: ctx)
        #expect(threads.count == 2)
        #expect(threads[0].bookId == "b-new")
        #expect(threads[1].bookId == "b-old")
    }

    @Test("threads for different users are isolated")
    func userIsolation() throws {
        let ctx = try makeInMemoryContext()
        let msg = [StoredAskMessage(question: "Q", selectionContext: nil, answer: "A", citations: [])]

        AskThreadStore.upsertThread(bookId: "b-shared", userId: "user-a", bookTitle: nil, messages: msg, context: ctx)
        AskThreadStore.upsertThread(bookId: "b-shared", userId: "user-b", bookTitle: nil, messages: msg, context: ctx)

        let aThreads = AskThreadStore.allThreads(userId: "user-a", context: ctx)
        let bThreads = AskThreadStore.allThreads(userId: "user-b", context: ctx)

        #expect(aThreads.count == 1)
        #expect(bThreads.count == 1)
        #expect(aThreads[0].threadId != bThreads[0].threadId)
    }

    // MARK: - AskTheBookModel persistence tests

    @Test("repository account authority keys A and B threads without a fallback identity")
    func repositoryAccountAuthorityIsolatesThreads() async throws {
        let ctx = try makeInMemoryContext()
        let accountA = FakeAIRepository(delay: 0, accountID: "account-a")
        let accountB = FakeAIRepository(delay: 0, accountID: "account-b")
        let modelA = AskTheBookModel(
            bookId: "b-shared",
            repository: accountA,
            modelContext: ctx
        )
        let modelB = AskTheBookModel(
            bookId: "b-shared",
            repository: accountB,
            modelContext: ctx
        )

        #expect(modelA.accountID == "account-a")
        #expect(modelB.accountID == "account-b")

        modelA.inputText = "Question from A"
        await modelA.sendQuestion()
        modelB.inputText = "Question from B"
        await modelB.sendQuestion()

        let aMessages = AskThreadStore.loadMessages(
            bookId: "b-shared",
            userId: "account-a",
            context: ctx
        )
        let bMessages = AskThreadStore.loadMessages(
            bookId: "b-shared",
            userId: "account-b",
            context: ctx
        )
        #expect(aMessages.map(\.question) == ["Question from A"])
        #expect(bMessages.map(\.question) == ["Question from B"])
        #expect(AskThreadStore.loadMessages(
            bookId: "b-shared",
            userId: "local",
            context: ctx
        ).isEmpty)
    }

    @Test("sendQuestion persists the message to SwiftData")
    func sendQuestionPersists() async throws {
        let ctx = try makeInMemoryContext()
        let repo = FakeAIRepository(
            response: FakeAIRepository.sampleResponse,
            delay: 0,
            accountID: "u1"
        )
        let model = AskTheBookModel(
            bookId: "b-habits",
            bookTitle: "Atomic Habits",
            repository: repo,
            modelContext: ctx
        )

        model.inputText = "What is the habit loop?"
        await model.sendQuestion()

        let stored = AskThreadStore.loadMessages(bookId: "b-habits", userId: "u1", context: ctx)
        #expect(stored.count == 1)
        #expect(stored[0].question == "What is the habit loop?")
    }

    @Test("model loads history from SwiftData on init")
    func loadsHistoryOnInit() async throws {
        let ctx = try makeInMemoryContext()
        let prior = [
            StoredAskMessage(question: "Prior Q", selectionContext: nil, answer: "Prior A", citations: [2]),
        ]
        AskThreadStore.upsertThread(bookId: "b-habits", userId: "u1", bookTitle: nil, messages: prior, context: ctx)

        let repo = FakeAIRepository(delay: 0, accountID: "u1")
        let model = AskTheBookModel(
            bookId: "b-habits",
            repository: repo,
            modelContext: ctx
        )

        #expect(model.messages.count == 1)
        #expect(model.messages[0].question == "Prior Q")
        #expect(model.messages[0].citations == [2])
    }

    @Test("saveToNotebook marks message as pinned")
    func saveToNotebookMarksPinned() async throws {
        let ctx = try makeInMemoryContext()
        let repo = FakeAIRepository(
            response: FakeAIRepository.sampleResponse,
            delay: 0,
            accountID: "u1"
        )
        let model = AskTheBookModel(
            bookId: "b-habits",
            repository: repo,
            modelContext: ctx
        )

        model.inputText = "What is the 1% rule?"
        await model.sendQuestion()

        let message = model.messages[0]
        #expect(model.pinnedMessageIds.isEmpty)

        model.saveToNotebook(message)
        #expect(model.pinnedMessageIds.contains(message.id.uuidString))
    }

    @Test("saveToNotebook inserts a CachedNotebookEntry locally")
    func saveToNotebookInsertsEntry() async throws {
        let ctx = try makeInMemoryContext()
        let repo = FakeAIRepository(
            response: FakeAIRepository.sampleResponse,
            delay: 0,
            accountID: "u1"
        )
        let model = AskTheBookModel(
            bookId: "b-habits",
            bookTitle: "Atomic Habits",
            repository: repo,
            modelContext: ctx
        )

        model.inputText = "How do habits compound?"
        await model.sendQuestion()
        model.saveToNotebook(model.messages[0])

        let notebookCount = try ctx.fetchCount(FetchDescriptor<CachedNotebookEntry>())
        #expect(notebookCount == 1)

        let mutationCount = try ctx.fetchCount(FetchDescriptor<PendingMutation>())
        #expect(mutationCount == 1)
    }

    @Test("shareText includes book title and citation attribution")
    func shareTextAttribution() async throws {
        let ctx = try makeInMemoryContext()
        let repo = FakeAIRepository(
            response: FakeAIRepository.sampleResponse,
            delay: 0,
            accountID: "u1"
        )
        let model = AskTheBookModel(
            bookId: "b-habits",
            bookTitle: "Atomic Habits",
            repository: repo,
            modelContext: ctx
        )

        model.inputText = "What is the core idea?"
        await model.sendQuestion()

        let text = model.shareText(for: model.messages[0])
        #expect(text.contains("Q: What is the core idea?"))
        #expect(text.contains("A:"))
        #expect(text.contains("Atomic Habits"))
        #expect(text.contains("Ch."))
    }

    @Test("sendQuestion includes conversation history on follow-up questions")
    func followUpIncludesHistory() async throws {
        let ctx = try makeInMemoryContext()
        let capturingRepo = CapturingAIRepository(accountID: "u1")
        let model = AskTheBookModel(
            bookId: "b-habits",
            repository: capturingRepo,
            modelContext: ctx
        )

        model.inputText = "First question"
        await model.sendQuestion()

        model.inputText = "Follow-up question"
        await model.sendQuestion()

        let lastCall = await capturingRepo.lastCall
        #expect(lastCall?.conversationHistory?.isEmpty == false)
        #expect(lastCall?.conversationHistory?.first?.question == "First question")
    }

    @Test("first question has nil conversationHistory")
    func firstQuestionHasNilHistory() async throws {
        let ctx = try makeInMemoryContext()
        let capturingRepo = CapturingAIRepository(accountID: "u1")
        let model = AskTheBookModel(
            bookId: "b-habits",
            repository: capturingRepo,
            modelContext: ctx
        )

        model.inputText = "First question ever"
        await model.sendQuestion()

        let lastCall = await capturingRepo.lastCall
        #expect(lastCall?.conversationHistory == nil)
    }

    @Test("quota is respected: rateLimited phase does not block reading cached history")
    func rateLimitedAllowsReadingHistory() async throws {
        let ctx = try makeInMemoryContext()

        let prior = [
            StoredAskMessage(question: "Old Q", selectionContext: nil, answer: "Old A", citations: [1]),
        ]
        AskThreadStore.upsertThread(bookId: "b-habits", userId: "u1", bookTitle: nil, messages: prior, context: ctx)

        let repo = FakeAIRepository(
            error: FakeAIRepository.rateLimitedError,
            delay: 0,
            accountID: "u1"
        )
        let model = AskTheBookModel(
            bookId: "b-habits",
            repository: repo,
            modelContext: ctx
        )

        #expect(model.messages.count == 1, "History loaded despite rate limit")
        #expect(model.messages[0].question == "Old Q")

        model.inputText = "New Q"
        await model.sendQuestion()

        if case .rateLimited = model.phase {
            // expected
        } else {
            Issue.record("Expected rateLimited phase, got \(model.phase)")
        }

        #expect(model.messages.count == 1, "History count unchanged after 429")
    }
}
