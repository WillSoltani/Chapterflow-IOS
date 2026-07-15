import Foundation
import Observation
import SwiftData
import CoreKit
import Models
import Persistence
import OSLog

private let log = Logger(subsystem: "com.chapterflow.ai", category: "AskTheBookModel")

/// The phase the "Ask the book" sheet is in.
public enum AskPhase: Equatable {
    /// Ready for input.
    case idle
    /// A question is in flight.
    case asking
    /// The server returned HTTP 429 — daily quota exhausted.
    /// `resetsAt` is the optional reset time derived from `Retry-After`.
    case rateLimited(resetsAt: Date?)
    /// A recoverable error occurred; `message` is user-facing.
    case error(String)
    /// The device has no network connection and on-device AI is unavailable.
    case offline
}

/// Observable view model for the "Ask the book" chat sheet.
///
/// Owns the in-memory message thread for one book session. Each call to
/// ``sendQuestion()`` fires the live repository and appends the result.
/// Past Q&A exchanges are loaded from the SwiftData store on init and
/// persisted automatically after every successful answer.
///
/// **Offline fallback (P6.5):** When the network is unavailable and an
/// ``OnDeviceAIProviding`` service is supplied together with ``chapterText``,
/// the model automatically answers using the on-device model — no user action
/// required. Answers generated this way carry `isOnDeviceAnswer = true`.
///
/// **P6.7 additions:** persistence + history, save-to-notebook, copy/share
/// with attribution, and conversation threading for follow-up questions.
@Observable
@MainActor
public final class AskTheBookModel {

    // MARK: - State

    /// Current UI phase (loading / rate-limited / error / offline / idle).
    public private(set) var phase: AskPhase = .idle

    /// The conversation thread for this book in the current session.
    /// Populated from the SwiftData cache on init, then appended live.
    public private(set) var messages: [AskMessage] = []

    /// How many questions the user may still ask today (nil = unknown).
    public private(set) var remainingQuota: Int?

    /// The text currently in the input field.
    public var inputText: String = ""

    /// The set of message IDs that have been pinned/saved to the notebook.
    public private(set) var pinnedMessageIds: Set<String> = []

    // MARK: - Configuration

    /// The book this model is asking about.
    public let bookId: String

    /// Optional book title used for copy/share attribution.
    public let bookTitle: String?

    /// Immutable account authority used for thread and outbox keying.
    public let accountID: String

    /// Optional highlighted passage shown as a context chip; sent with every request.
    public let selectionContext: String?

    /// The reader's tone preference; forwarded to the API for grounded answers.
    public let tone: String?

    /// Pre-extracted plain text of the current chapter used as grounding context
    /// for the on-device offline fallback. Truncated internally before use.
    public let chapterText: String?

    // MARK: - Navigation callback

    /// Called when the user taps a citation chip to jump to that chapter.
    public var onJumpToChapter: ((Int) -> Void)?

    // MARK: - Private

    private let repository: any AIRepository
    private let onDeviceService: (any OnDeviceAIProviding)?
    /// SwiftData context for thread persistence. Nil → in-memory only (previews/tests).
    private let modelContext: ModelContext?

    // MARK: - Init

    public init(
        bookId: String,
        bookTitle: String? = nil,
        repository: any AIRepository,
        selectionContext: String? = nil,
        tone: String? = nil,
        chapterText: String? = nil,
        onDeviceService: (any OnDeviceAIProviding)? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.bookId = bookId
        self.accountID = repository.accountID
        self.bookTitle = bookTitle
        self.repository = repository
        self.selectionContext = selectionContext
        self.tone = tone
        self.chapterText = chapterText
        self.onDeviceService = onDeviceService
        self.modelContext = modelContext
        loadPersistedThread()
    }

    // MARK: - Actions

    /// Sends `inputText` as a question to the server and appends the answer.
    ///
    /// Passes the last few messages as conversation history so follow-up
    /// questions are coherent. When the network is unavailable and an on-device
    /// service + chapter text were provided, falls back to an on-device answer
    /// automatically. Every successful answer is persisted to the SwiftData store.
    public func sendQuestion() async {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase != .asking else { return }

        inputText = ""
        phase = .asking

        let history = buildConversationHistory()

        do {
            let response = try await repository.askBook(
                bookId: bookId,
                question: question,
                selectionContext: selectionContext,
                tone: tone,
                conversationHistory: history
            )
            let message = AskMessage(
                question: question,
                selectionContext: selectionContext,
                answer: response.answer,
                citations: response.citations
            )
            messages.append(message)
            if let quota = response.remainingQuestions {
                remainingQuota = quota
            }
            phase = .idle
            persistThread()
        } catch let appError as AppError {
            if case .offline = appError, let service = onDeviceService {
                await handleOfflineWithOnDevice(question: question, service: service)
            } else {
                handleError(appError, question: question)
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Dismisses an error or offline state so the user can retry.
    public func retry() {
        phase = .idle
    }

    /// Triggers the chapter-jump callback.
    public func jumpToChapter(_ number: Int) {
        onJumpToChapter?(number)
    }

    /// Saves an answer to the user's notebook as a note entry.
    ///
    /// Creates a local ``CachedNotebookEntry`` immediately and queues a
    /// ``PendingMutation`` so the SyncEngine uploads it when online.
    public func saveToNotebook(_ message: AskMessage) {
        guard let context = modelContext else { return }

        let entryId = UUID().uuidString
        let content = buildNotebookContent(question: message.question, answer: message.answer)
        let now = ISO8601DateFormatter().string(from: Date())

        // 1. Cache locally for immediate notebook display.
        let domain = NotebookEntry(
            entryId: entryId,
            bookId: bookId,
            chapterId: nil,
            type: .note,
            content: content,
            quote: message.selectionContext,
            createdAt: now,
            updatedAt: now,
            bookTitle: bookTitle,
            tags: ["ai-answer"]
        )
        if let cached = try? CachedNotebookEntry.from(domain, userId: accountID) {
            context.insert(cached)
        }

        // 2. Queue a server write for the SyncEngine.
        // Uses an inline Codable payload matching the NotebookWritePayload wire format
        // so AIFeature doesn't need to depend on SyncEngine.
        struct AINotebookWritePayload: Encodable {
            let entryId: String?
            let bookId: String
            let chapterId: String
            let type: String
            let content: String?
            let quote: String?
            let color: String?
        }
        let payload = AINotebookWritePayload(
            entryId: nil,
            bookId: bookId,
            chapterId: "",
            type: NotebookEntryType.note.rawValue,
            content: content,
            quote: message.selectionContext,
            color: nil
        )
        if let mutation = try? PendingMutation.make(
            userId: accountID,
            kind: .notebookWrite,
            payload: payload
        ) {
            context.insert(mutation)
        }

        do {
            try context.save()
        } catch {
            log.error("AskTheBookModel: notebook save failed — \(error.localizedDescription)")
        }

        // 3. Mark message as pinned in the thread.
        pinnedMessageIds.insert(message.id.uuidString)
        updateStoredPinState(messageId: message.id.uuidString, isPinned: true)
    }

    /// Returns a share-ready string for an answer with attribution.
    public func shareText(for message: AskMessage) -> String {
        var parts: [String] = []
        parts.append("Q: \(message.question)")
        parts.append("")
        parts.append("A: \(message.answer)")
        if !message.citations.isEmpty {
            let chapList = message.citations.map { "Ch. \($0)" }.joined(separator: ", ")
            parts.append("")
            parts.append("Sources: \(chapList)")
        }
        if let title = bookTitle {
            parts.append("")
            parts.append("— \(title) via ChapterFlow")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Whether a question can currently be submitted.
    public var canSend: Bool {
        phase == .idle && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the on-device service and chapter text are both injected.
    public var isOnDeviceWired: Bool {
        onDeviceService != nil && !(chapterText ?? "").isEmpty
    }

    /// True when on-device offline answering is wired up and available.
    public var isOnDeviceAvailable: Bool {
        get async {
            guard let service = onDeviceService,
                  let text = chapterText, !text.isEmpty else { return false }
            return await service.availability.isAvailable && !text.isEmpty
        }
    }

    // MARK: - Private helpers

    /// Loads the persisted thread from SwiftData and seeds `messages`.
    private func loadPersistedThread() {
        guard let context = modelContext else { return }
        let stored = AskThreadStore.loadMessages(bookId: bookId, userId: accountID, context: context)
        messages = stored.map { $0.asAskMessage() }
        pinnedMessageIds = Set(stored.filter { $0.isPinned }.map { $0.id })
    }

    /// Saves the current in-memory thread to SwiftData.
    private func persistThread() {
        guard let context = modelContext else { return }
        let stored = messages.map { msg -> StoredAskMessage in
            var s = msg.toStored()
            s.isPinned = pinnedMessageIds.contains(msg.id.uuidString)
            return s
        }
        AskThreadStore.upsertThread(
            bookId: bookId,
            userId: accountID,
            bookTitle: bookTitle,
            messages: stored,
            context: context
        )
    }

    /// Updates the pin state for a single message in the SwiftData store.
    private func updateStoredPinState(messageId: String, isPinned: Bool) {
        guard let context = modelContext else { return }
        AskThreadStore.updatePinState(
            messageId: messageId,
            isPinned: isPinned,
            bookId: bookId,
            userId: accountID,
            context: context
        )
    }

    /// Builds the last few Q&A turns for the conversation history payload.
    /// Sends at most 5 recent turns to keep the request size bounded.
    private func buildConversationHistory() -> [AIConversationTurn]? {
        let recent = messages.suffix(5)
        guard !recent.isEmpty else { return nil }
        return recent.map { AIConversationTurn(question: $0.question, answer: $0.answer) }
    }

    /// Formats a Q&A pair as a notebook note body.
    private func buildNotebookContent(question: String, answer: String) -> String {
        "**Q:** \(question)\n\n**A:** \(answer)"
    }

    /// Attempts an on-device answer when the network is offline.
    private func handleOfflineWithOnDevice(question: String, service: any OnDeviceAIProviding) async {
        let state = await service.availability
        guard state.isAvailable, let text = chapterText, !text.isEmpty else {
            phase = .offline
            return
        }
        do {
            let answer = try await service.answerQuestion(
                question,
                chapterText: text,
                selectionContext: selectionContext
            )
            let message = AskMessage(
                question: question,
                selectionContext: selectionContext,
                answer: answer,
                citations: [],
                isOnDeviceAnswer: true
            )
            messages.append(message)
            phase = .idle
            persistThread()
        } catch {
            phase = .offline
        }
    }

    private func handleError(_ error: AppError, question: String) {
        switch error {
        case .rateLimited(let retryAfter):
            let resetDate = retryAfter.map { Date().addingTimeInterval($0) }
            phase = .rateLimited(resetsAt: resetDate)
        case .offline:
            phase = .offline
        default:
            phase = .error(error.errorDescription ?? "Something went wrong. Please try again.")
        }
    }
}
